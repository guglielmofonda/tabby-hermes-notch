import SwiftUI
import Combine
import DynamicNotchKit

@main
struct TabbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: DynamicNotch<NotchContentView, EmptyView, IdleTrailingView>?
    private var setupWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var pillClickMonitor: Any?
    private let state = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .hapticFeedback],
            expanded: { NotchContentView() },
            compactLeading: { EmptyView() },
            compactTrailing: { IdleTrailingView() }
        )
        self.notch = notch

        installStatusItem()
        installPillClickMonitor()

        // Pipe DynamicNotch's full-pill hover state into AppState so the idle icon
        // scales even when the cursor is over the pill's rounded-corner chrome.
        notch.$isHovering
            .receive(on: RunLoop.main)
            .sink { [weak self] hovering in
                self?.state.isPillHovering = hovering
            }
            .store(in: &cancellables)

        state.bootstrap()

        state.telegram.$authStep
            .receive(on: RunLoop.main)
            .sink { [weak self] step in
                self?.handle(step: step)
            }
            .store(in: &cancellables)

        state.$notchMode
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.handle(mode: mode)
            }
            .store(in: &cancellables)
    }

    /// Installs a local event monitor so a left-mouse-down anywhere inside the DynamicNotch
    /// panel — including the rounded-corner chrome that DynamicNotchKit draws outside the
    /// compactTrailing content — starts / stops recording. Only fires in idle (compact)
    /// state; expanded states keep their SwiftUI handlers.
    private func installPillClickMonitor() {
        guard pillClickMonitor == nil else { return }
        pillClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let notchWindow = self.notch?.windowController?.window else { return event }
            guard event.window === notchWindow else { return event }
            // Only hijack clicks when the notch is in its compact idle pill. Expanded states
            // (recording/transcribing/sending/waitingForHermes/showingConversation/error)
            // have SwiftUI buttons and tap gestures that must keep working.
            guard self.state.notchMode == .idle else { return event }
            Task { @MainActor in self.state.toggleRecording() }
            return nil
        }
    }

    private func handle(step: AuthStep) {
        switch step {
        case .authenticated:
            closeSetupWindow()
        case .launching:
            break
        default:
            showSetupWindow()
        }
    }

    private func handle(mode: AppState.NotchMode) {
        guard let notch else { return }
        switch mode {
        case .setupPending:
            Task { await notch.hide() }
        case .idle:
            Task { await notch.compact() }
        case .recording, .transcribing, .sending, .waitingForHermes, .showingConversation, .error:
            Task { await notch.expand() }
        }
    }

    // MARK: - Setup window

    private func showSetupWindow() {
        if let win = setupWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SetupWizardView().environmentObject(state))
        let win = NSWindow(contentViewController: hosting)
        win.title = "Tabby Setup"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 520, height: 440))
        win.center()
        win.isReleasedWhenClosed = false
        setupWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSetupWindow() {
        setupWindow?.orderOut(nil)
    }

    // MARK: - Status item + Settings

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Tabby")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Tabby Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Start Dictation", action: #selector(toggleRecordingAction), keyEquivalent: "d").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reset Telegram setup", action: #selector(resetTelegramAction), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tabby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "Tabby Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 460, height: 520))
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleRecordingAction() {
        state.toggleRecording()
    }

    @objc private func resetTelegramAction() {
        state.telegram.resetAuth()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = pillClickMonitor {
            NSEvent.removeMonitor(monitor)
            pillClickMonitor = nil
        }
        state.telegram.stop()
    }
}
