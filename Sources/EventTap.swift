import CoreGraphics
import Foundation

/// A thread with its own run loop for event taps, so input is never held up by work on the main thread
/// (window lists, rendering, a hung app answering slowly).
final class InputThread: Thread {
    /// Keyboard.
    static let shared = InputThread(name: "GlideTab keyboard")
    /// Trackpad. Separate because reading touches waits on the main thread, which the keyboard must never do.
    static let trackpad = InputThread(name: "GlideTab trackpad")

    private init(name: String) {
        super.init()
        self.name = name
        qualityOfService = .userInteractive
        start()
        ready.wait()
    }

    private let ready = DispatchSemaphore(value: 0)
    private(set) var runLoop: CFRunLoop!

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A run loop with no sources exits immediately; keep one around.
        var context = CFRunLoopSourceContext()
        CFRunLoopAddSource(runLoop, CFRunLoopSourceCreate(nil, 0, &context), .commonModes)
        ready.signal()
        CFRunLoopRun()
    }
}

/// A thin wrapper around a CGEventTap. The handler returns true to swallow the event (ignored for
/// listen-only taps). It runs on the input thread unless another run loop is given.
final class EventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let events: [CGEventType]
    private let location: CGEventTapLocation
    private let listenOnly: Bool
    private var wantsEnabled = true
    private let runLoop: CFRunLoop
    private let handler: (CGEventType, CGEvent) -> Bool
    /// Called (on the tap's thread) after macOS disabled the tap and it was turned back on: events were
    /// missed in between, e.g. the release of a modifier key.
    var onReenabled: (() -> Void)?

    init(events: [CGEventType], location: CGEventTapLocation = .cgSessionEventTap, listenOnly: Bool = false,
         runLoop: CFRunLoop = InputThread.shared.runLoop, handler: @escaping (CGEventType, CGEvent) -> Bool) {
        self.events = events
        self.location = location
        self.listenOnly = listenOnly
        self.runLoop = runLoop
        self.handler = handler
    }

    deinit { stop() }

    /// Fails until the app has the Accessibility permission.
    func start(enabled: Bool = true) -> Bool {
        if port != nil { return true }
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
            return tap.handle(type, event)
        }
        guard let port = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: listenOnly ? .listenOnly : .defaultTap,
                                           eventsOfInterest: mask, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
        self.port = port
        self.source = source
        setEnabled(enabled)
        return true
    }

    /// Takes the tap in or out of the event stream without recreating it.
    func setEnabled(_ enabled: Bool) {
        wantsEnabled = enabled
        if let port { CGEvent.tapEnable(tap: port, enable: enabled) }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        port = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS turns taps off if it thinks they're slow; turn ours straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port, wantsEnabled {
                CGEvent.tapEnable(tap: port, enable: true)
                onReenabled?()
            }
            return Unmanaged.passUnretained(event)
        }
        let swallow = handler(type, event)
        return swallow && !listenOnly ? nil : Unmanaged.passUnretained(event)
    }
}
