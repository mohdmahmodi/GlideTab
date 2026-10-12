import AppKit
import ScreenCaptureKit

/// ScreenCaptureKit snapshots, cached so the switcher draws instantly (minimized windows can't be captured).
/// Main thread only. At most one capture per window, and one full-size capture, is in flight at a time.
final class Thumbnails {
    static let shared = Thumbnails()

    private(set) var cache: [CGWindowID: CGImage] = [:]

    /// Size thumbnails are captured at, in points: the largest the switcher ever draws them (Auto size).
    private static let captureSize = CGSize(width: 220 * ThumbnailSize.auto.maxScale, height: 138 * ThumbnailSize.auto.maxScale)
    /// At most this many captures run at once; the rest wait their turn.
    private static let maxConcurrent = 6
    private var running = 0
    private var waiting: [() -> Void] = []

    private var inFlight: Set<CGWindowID> = []
    private var listeners: [CGWindowID: [(CGWindowID, CGImage) -> Void]] = [:]
    private var fullSizeBusy = false
    private var pendingFullSize: (id: CGWindowID, completion: (CGImage?) -> Void)?

    /// Listing shareable windows is the expensive part of a capture, so reuse it briefly, and never run two at once.
    private var content: (windows: [CGWindowID: SCWindow], date: Date)?
    private var contentWaiters: [([CGWindowID: SCWindow]) -> Void] = []

    /// Captures fresh thumbnails. `onImage` is called as each arrives.
    func capture(ids: [CGWindowID], onImage: ((CGWindowID, CGImage) -> Void)? = nil) {
        // Only the thumbnail style needs pixels.
        guard !ids.isEmpty, Prefs.style == .thumbnails, Permissions.screenRecording else { return }
        if let onImage { for id in ids { listeners[id, default: []].append(onImage) } }
        let newIDs = ids.filter { inFlight.insert($0).inserted }
        guard !newIDs.isEmpty else { return }
        shareableWindows(maxAge: 0.5) { windows in
            for id in newIDs {
                guard let window = windows[id] else {
                    self.finish(id, nil)
                    continue
                }
                self.throttled { done in
                    self.capture(window, maxSize: Self.captureSize) { image in
                        self.finish(id, image)
                        done()
                    }
                }
            }
        }
    }

    func capture(_ windows: [WindowInfo], onImage: ((CGWindowID, CGImage) -> Void)? = nil) {
        capture(ids: windows.filter { !$0.isMinimized && !$0.app.isHidden }.map(\.id), onImage: onImage)
    }

    private func finish(_ id: CGWindowID, _ image: CGImage?) {
        inFlight.remove(id)
        let waiting = listeners.removeValue(forKey: id) ?? []
        guard let image else { return }
        cache[id] = image
        waiting.forEach { $0(id, image) }
    }

    /// A full-resolution capture for the selected-window preview, with nil on failure.
    /// If one is already running, only the most recent request is kept.
    func captureFullSize(_ id: CGWindowID, completion: @escaping (CGImage?) -> Void) {
        guard Permissions.screenRecording else { return completion(nil) }
        if fullSizeBusy {
            pendingFullSize?.completion(nil)
            pendingFullSize = (id, completion)
            return
        }
        fullSizeBusy = true
        shareableWindows(maxAge: 5) { windows in
            let done: (CGImage?) -> Void = { image in
                completion(image)
                self.fullSizeBusy = false
                if let next = self.pendingFullSize {
                    self.pendingFullSize = nil
                    self.captureFullSize(next.id, completion: next.completion)
                }
            }
            guard let window = windows[id] else { return done(nil) }
            self.capture(window, maxSize: window.frame.size, completion: done)
        }
    }

    func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }

    /// Delivers the current shareable windows on the main thread.
    private func shareableWindows(maxAge: TimeInterval, _ body: @escaping ([CGWindowID: SCWindow]) -> Void) {
        if let content, Date().timeIntervalSince(content.date) < maxAge { return body(content.windows) }
        contentWaiters.append(body)
        guard contentWaiters.count == 1 else { return }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, _ in
            var byID: [CGWindowID: SCWindow] = [:]
            for window in content?.windows ?? [] { byID[window.windowID] = window }
            DispatchQueue.main.async {
                if content != nil { self.content = (byID, Date()) }
                let waiters = self.contentWaiters
                self.contentWaiters = []
                waiters.forEach { $0(byID) }
            }
        }
    }

    private func throttled(_ work: @escaping (_ done: @escaping () -> Void) -> Void) {
        let run = {
            self.running += 1
            work {
                self.running -= 1
                if !self.waiting.isEmpty { self.waiting.removeFirst()() }
            }
        }
        if running < Self.maxConcurrent { run() } else { waiting.append(run) }
    }

    /// Always calls `completion` exactly once, on the main thread.
    private func capture(_ window: SCWindow, maxSize: CGSize, completion: @escaping (CGImage?) -> Void) {
        guard window.frame.width > 0, window.frame.height > 0 else { return completion(nil) }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // The pixel density of the display the window is on, so thumbnails are sharp on mixed-DPI setups.
        let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
        let fit = min(maxSize.width / window.frame.width, maxSize.height / window.frame.height, 1) * max(scale, 1)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * fit))
        config.height = max(1, Int(window.frame.height * fit))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }
}
