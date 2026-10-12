import AppKit

/// Shows the selected window full size, where it really is, just below the switcher panel.
final class PreviewWindow: NSPanel {
    private let imageLayer = CALayer()
    private var request = 0
    /// The window currently on screen in the preview, if any.
    private(set) var shownWindowID: CGWindowID?
    /// Changes whenever the preview is shown or hidden.
    var token: Int { request }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        imageLayer.contentsGravity = .resize
        view.layer?.addSublayer(imageLayer)
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    /// Captures and shows `window`, unless another call or `hide()` comes first.
    func show(_ window: WindowInfo?) {
        request += 1
        let current = request
        guard let window, !window.isMinimized, !window.app.isHidden, window.frame.width > 0,
              let primary = NSScreen.screens.first else { return hide() }
        // Wait a beat so fast Tab-cycling doesn't capture every window it passes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.request == current else { return }
            Thumbnails.shared.captureFullSize(window.id) { [weak self] image in
                guard let self, self.request == current else { return }
                guard let image else { return self.hide() }
                let frame = CGRect(x: window.frame.minX, y: primary.frame.maxY - window.frame.maxY,
                                   width: window.frame.width, height: window.frame.height)
                self.crossfade(to: image, frame: frame, request: current) { self.shownWindowID = window.id }
            }
        }
    }

    /// Fades the old picture out and the new one in, rather than jumping across the screen.
    private func crossfade(to image: CGImage, frame: CGRect, request current: Int, shown: @escaping () -> Void) {
        let place = {
            self.setFrame(frame, display: false)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.imageLayer.frame = CGRect(origin: .zero, size: frame.size)
            self.imageLayer.contents = image
            CATransaction.commit()
            self.orderFrontRegardless()
            shown()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.animator().alphaValue = 1
            }
        }
        guard isVisible, alphaValue > 0 else {
            alphaValue = 0
            return place()
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.07
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.request == current else { return }
            place()
        })
    }

    func hide() {
        request += 1
        shownWindowID = nil
        imageLayer.contents = nil
        orderOut(nil)
    }

    /// Fades out once the real window is in front, unless a newer request has replaced the preview.
    func fadeOut(ifStill token: Int) {
        guard token == request else { return }
        let current = request
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.request == current else { return }
            self.hide()
        })
    }
}
