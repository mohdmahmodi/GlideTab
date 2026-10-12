import AppKit
import Combine
import SwiftUI

/// The first-run window: explains each permission before macOS asks for it, and ends on a "ready" screen.
/// The current step is saved, so it picks up where it left off after macOS relaunches the app for Screen Recording.
enum Onboarding {
    enum Step: String, CaseIterable {
        case welcome, accessibility, previews, ready, done
    }

    static var step: Step {
        get { Step(rawValue: UserDefaults.standard.string(forKey: Prefs.Key.onboarding) ?? "") ?? .welcome }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Prefs.Key.onboarding) }
    }

    /// Copies that already work (Accessibility granted before this window existed) skip it.
    static var isNeeded: Bool {
        if UserDefaults.standard.string(forKey: Prefs.Key.onboarding) == nil, Permissions.accessibility {
            step = .done
        }
        return step != .done
    }

    /// Ends setup from Done, or from the close button once Accessibility is on.
    static func finish() {
        step = .done
        // Thumbnails can't be drawn without Screen Recording, so fall back to the App Icons style.
        if !Permissions.screenRecording && Prefs.style == .thumbnails {
            UserDefaults.standard.set(SwitcherStyle.icons.rawValue, forKey: Prefs.Key.style)
        }
        if !UserDefaults.standard.bool(forKey: Prefs.Key.didSetUpLoginItem) {
            UserDefaults.standard.set(true, forKey: Prefs.Key.didSetUpLoginItem)
            LoginItem.isEnabled = true
        }
    }

    static func makeWindow(onFinish: @escaping () -> Void) -> NSWindow {
        let controller = NSHostingController(rootView: OnboardingView(onFinish: onFinish))
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Welcome to GlideTab")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 600, height: 540))
        window.center()
        return window
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = Onboarding.step == .done ? .ready : Onboarding.step
    @State private var accessibility = Permissions.accessibility
    @State private var screenRecording = Permissions.screenRecording
    // Until setup ends, the login item isn't registered yet; it will be, unless unchecked here.
    @State private var launchAtLogin = !UserDefaults.standard.bool(forKey: Prefs.Key.didSetUpLoginItem) || LoginItem.isEnabled
    @State private var askedForAccessibility = false
    @State private var askedForScreenRecording = false
    private let poll = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    private var pages: [Onboarding.Step] { [.welcome, .accessibility, .previews, .ready] }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome, .done: welcome
                case .accessibility: accessibilityPage
                case .previews: previewsPage
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .transition(.opacity)
            .id(step)

            dots
            Divider()
            footer
        }
        .frame(width: 600, height: 540)
        .ignoresSafeArea() // The title bar is transparent; the layout already leaves room for its buttons.
        .onReceive(poll) { _ in refresh() }
        .onChange(of: step) { _, new in Onboarding.step = new }
        .onChange(of: launchAtLogin) { _, new in
            UserDefaults.standard.set(true, forKey: Prefs.Key.didSetUpLoginItem)
            if new != LoginItem.isEnabled { LoginItem.isEnabled = new }
        }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to GlideTab").font(.system(size: 28, weight: .bold))
            Text("Hold Option and press Tab to see every open window, then let go to switch.")
                .font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                MacKey(topLeft: "⌥", bottomLeft: "option", width: 1.5, scale: 1.5)
                Text("+").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                MacKey(topLeft: "⇥", bottomLeft: "tab", width: 1.5, scale: 1.5)
            }
            .padding(.vertical, 10)
            Label("Everything stays on your Mac. No account, no tracking, nothing uploaded.", systemImage: "lock.shield")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var accessibilityPage: some View {
        PermissionPage(
            symbol: "accessibility", color: .blue,
            title: "Let GlideTab see your shortcut",
            message: "macOS asks before any app can respond to a shortcut from anywhere or bring another app's window forward. That's what Accessibility allows.",
            points: [
                "It only reacts to its own shortcut, and to typing while the switcher is open.",
                "It never saves or sends anything you type.",
                "You can turn it off at any time in System Settings.",
            ],
            granted: accessibility, grantedText: "Accessibility is on",
            hint: "Turn on GlideTab in the list, then come back here.")
    }

    private var previewsPage: some View {
        PermissionPage(
            symbol: "rectangle.on.rectangle", color: .teal,
            title: "Show live previews",
            message: "To show thumbnails of your windows, macOS asks for Screen Recording. It's optional: the App Icons and List styles work without it.",
            points: [
                "By default, it only takes still pictures of windows while the switcher is open.",
                "It never records video or sound, and never saves or uploads anything.",
                "macOS will ask to quit and reopen GlideTab. It comes right back to this step.",
            ],
            granted: screenRecording, grantedText: "Screen Recording is on", hint: nil)
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("You're all set").font(.system(size: 28, weight: .bold))
            Text("Hold ⌥ Option, press Tab, and let go to switch.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                tip("GlideTab lives in the menu bar.", symbol: "rectangle.on.rectangle")
                tip("Type while the switcher is open to search.", symbol: "magnifyingglass")
            }
            .font(.system(size: 14))
            .padding(18)
            .frame(maxWidth: 380, alignment: .leading)
            .cardBackground()
            Toggle("Open at login", isOn: $launchAtLogin).toggleStyle(.checkbox)
        }
    }

    private func tip(_ text: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(pages, id: \.self) { page in
                Circle()
                    .fill(page == step ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 18)
        .accessibilityHidden(true)
    }

    /// Back on the left, the way forward on the right, like Setup Assistant.
    private var footer: some View {
        HStack(spacing: 10) {
            if step == .accessibility || step == .previews {
                Button("Back") { go(-1) }.controlSize(.large)
            }
            Spacer()
            if step == .previews && !screenRecording {
                Button("Skip") { go(1) }.controlSize(.large)
            }
            Button(primaryTitle, action: primaryAction)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .welcome, .done: "Get Started"
        case .accessibility: accessibility ? "Continue" : askedForAccessibility ? "Open System Settings" : "Grant Access…"
        case .previews: screenRecording ? "Continue" : askedForScreenRecording ? "Open System Settings" : "Grant Access…"
        case .ready: "Done"
        }
    }

    /// The first click shows the macOS prompt. macOS shows it only once, so later clicks open the pane instead.
    private func primaryAction() {
        switch step {
        case .welcome, .done:
            go(1)
        case .accessibility:
            if accessibility {
                go(1)
            } else if !askedForAccessibility {
                askedForAccessibility = true
                Permissions.requestAccessibility()
            } else {
                Permissions.openSettings("Privacy_Accessibility")
            }
        case .previews:
            if screenRecording {
                go(1)
            } else if !askedForScreenRecording {
                askedForScreenRecording = true
                CGRequestScreenCaptureAccess()
            } else {
                Permissions.openSettings("Privacy_ScreenCapture")
            }
        case .ready:
            Onboarding.finish()
            onFinish()
        }
    }

    private func go(_ offset: Int) {
        guard let index = pages.firstIndex(of: step), pages.indices.contains(index + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = pages[index + offset] }
    }

    private func refresh() {
        let wasAllowed = accessibility
        accessibility = Permissions.accessibility
        screenRecording = Permissions.screenRecording
        // Move on by itself once Accessibility is turned on, and bring this window back to the front.
        if step == .accessibility && accessibility && !wasAllowed {
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if step == .accessibility { go(1) } }
        }
    }
}

/// One permission page: what it's for, what it doesn't do, and whether it's on yet.
private struct PermissionPage: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let points: [LocalizedStringKey]
    let granted: Bool
    let grantedText: LocalizedStringKey
    let hint: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(.white))
            Text(title).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(points.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.green)
                        Text(points[i]).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 13))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            if granted {
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.green)
            } else if let hint {
                Text(hint).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
    }
}
