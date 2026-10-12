import AppKit

/// The macOS trackpad gestures that use the same fingers as ours. Read from the system's trackpad settings
/// (built-in and Magic Trackpad), so Settings can say what to change.
enum SystemGestureConflict {
    case threeFingerDrag
    case fullScreenSwipe

    static func current(fingers: Int) -> SystemGestureConflict? {
        let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
        func value(_ key: String) -> Int {
            domains.compactMap { UserDefaults(suiteName: $0)?.object(forKey: key) as? Int }.max() ?? 0
        }
        if fingers == 3 && value("TrackpadThreeFingerDrag") == 1 { return .threeFingerDrag }
        // 2 means "Swipe between full-screen apps" (which also moves between Spaces).
        let swipe = fingers == 3 ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
        return value(swipe) == 2 ? .fullScreenSwipe : nil
    }

    /// The System Settings pane where it's turned off.
    var settingsURL: URL {
        switch self {
        case .threeFingerDrag: URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?PointerControl")!
        case .fullScreenSwipe: URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!
        }
    }
}

enum GestureOutput: Equatable {
    case begin(reverse: Bool)
    case step(Int)
    case end
}

/// Turns trackpad finger positions into switcher steps. With exactly `fingers` touching, a sideways swipe past
/// `trigger` opens the switcher and each further `step` moves the selection; lifting a finger ends it.
/// Vertical swipes are ignored, so Mission Control still works.
struct GestureRecognizer {
    var fingers: Int
    /// Distances in normalized trackpad units (0…1).
    var trigger: Double
    var step: Double

    private var anchor: CGPoint?
    private var started = false
    private var ignored = false

    var isActive: Bool { started }

    init(fingers: Int = 3, trigger: Double = 0.06, step: Double = 0.05) {
        self.fingers = fingers
        self.trigger = trigger
        self.step = step
    }

    /// `touches` are the positions of the fingers currently down. Events with no touch information at all
    /// must not be passed in (macOS sends those between real ones).
    mutating func update(_ touches: [CGPoint]) -> [GestureOutput] {
        guard touches.count == fingers else {
            let wasStarted = started
            anchor = nil
            started = false
            ignored = false
            return wasStarted ? [.end] : []
        }
        let center = CGPoint(x: touches.map(\.x).reduce(0, +) / CGFloat(touches.count),
                             y: touches.map(\.y).reduce(0, +) / CGFloat(touches.count))
        guard var origin = anchor else {
            anchor = center
            return []
        }
        guard !ignored else { return [] }

        let dx = Double(center.x - origin.x), dy = Double(center.y - origin.y)
        var output: [GestureOutput] = []
        if !started {
            if abs(dy) >= trigger && abs(dy) > abs(dx) {
                ignored = true // a vertical swipe: not ours
                return []
            }
            guard abs(dx) >= trigger else { return [] }
            started = true
            output.append(.begin(reverse: dx < 0))
            origin.x = center.x // later steps count from here
        }
        var remaining = Double(center.x - origin.x)
        while abs(remaining) >= step {
            let direction = remaining < 0 ? -1 : 1
            output.append(.step(direction))
            origin.x += CGFloat(Double(direction) * step)
            remaining = Double(center.x - origin.x)
        }
        anchor = origin
        return output
    }
}

/// Feeds trackpad touches to a GestureRecognizer on the trackpad thread, where `onOutput` is called. Installed
/// only while the gesture is on. A listen-only HID tap detects; a second tap, enabled only while enough fingers
/// are down, swallows the swipe so it doesn't also scroll the app underneath.
final class TrackpadMonitor {
    private var detectTap: EventTap?
    private var absorbTap: EventTap?
    private var recognizer = GestureRecognizer()
    private var absorbing = false
    private var absorbArmed = false
    private let onOutput: (GestureOutput) -> Void

    init(onOutput: @escaping (GestureOutput) -> Void) {
        self.onOutput = onOutput
    }

    /// Called from the main thread; applied on the trackpad thread, which owns this object's state.
    func configure(fingers: Int?) {
        let runLoop = InputThread.trackpad.runLoop!
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in self?.apply(fingers: fingers) }
        CFRunLoopWakeUp(runLoop)
    }

    private func apply(fingers: Int?) {
        guard let fingers else {
            detectTap?.stop()
            absorbTap?.stop()
            detectTap = nil
            absorbTap = nil
            return
        }
        if recognizer.fingers != fingers { recognizer = GestureRecognizer(fingers: fingers) }
        guard detectTap == nil else { return }
        let gesture = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        // Created first so it usually runs second (taps at the same point run newest first). If the order
        // ever flips, swallowing starts one event late, which is harmless.
        let runLoop = InputThread.trackpad.runLoop!
        let absorb = EventTap(events: [gesture], location: .cghidEventTap, runLoop: runLoop) { [unowned self] _, _ in
            self.absorbing
        }
        let detect = EventTap(events: [gesture], location: .cghidEventTap, listenOnly: true, runLoop: runLoop) {
            [unowned self] _, event in
            self.handle(event)
            return false
        }
        guard absorb.start(enabled: false), detect.start() else { return }
        absorbTap = absorb
        detectTap = detect
    }

    private func handle(_ event: CGEvent) {
        guard let fingers = Fingers(event) else { return }
        let points = fingers.count == recognizer.fingers
            ? fingers.positions
            : Array(repeating: .zero, count: fingers.count) // only the count matters here
        for output in recognizer.update(points) { onOutput(output) }
        absorbing = recognizer.isActive
        // Changing a tap is a call to the window server, so only at gesture boundaries.
        let armed = fingers.count >= recognizer.fingers || recognizer.isActive
        if armed != absorbArmed {
            absorbArmed = armed
            absorbTap?.setEnabled(armed)
        }
    }
}

/// The trackpad fingers resting on the surface during a gesture event.
private struct Fingers {
    let count: Int
    /// Normalized (0…1) positions; can be shorter than `count` if a touch has no readable position.
    let positions: [CGPoint]

    /// nil for the touchless events macOS sends in between real ones: they say nothing about the fingers.
    init?(_ event: CGEvent) {
        // AppKit only fills in touch data when the event is converted on the main thread.
        let read = { () -> Fingers? in
            guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
            let trackpad = nsEvent.touches(matching: .any, in: nil).filter { $0.type == .indirect }
            guard !trackpad.isEmpty else { return nil }
            let resting = trackpad.filter { $0.phase.isSubset(of: .touching) }
            return Fingers(count: resting.count, positions: resting.compactMap(Self.position))
        }
        guard let fingers = Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read) else { return nil }
        self = fingers
    }

    private init(count: Int, positions: [CGPoint]) {
        self.count = count
        self.positions = positions
    }

    /// Some touches (Universal Control, for one) raise an exception instead of returning a position.
    private static func position(of touch: NSTouch) -> CGPoint? {
        var point = CGPoint.zero
        return ObjCCatch { point = touch.normalizedPosition } == nil ? point : nil
    }
}
