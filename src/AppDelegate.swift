import Cocoa
import SwiftUI
import Carbon
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private var store: ClipStore!
    private var monitor: PasteboardMonitor!
    private var clickMonitor: Any?
    private var hotkeyRef: EventHotKeyRef?
    private var lastHideTime: Date?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = ClipStore()
        monitor = PasteboardMonitor()
        monitor.onNewClip = { [weak self] item in
            DispatchQueue.main.async {
                self?.store.add(item)
            }
        }
        monitor.start()

        setupPanel()
        setupStatusItem()
        registerHotkey()
        registerLoginItem()

        NotificationCenter.default.addObserver(
            forName: .dismissShelfPanel, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard.fill",
                                   accessibilityDescription: "Shelf")
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Shelf", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Shelf", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    // MARK: - Panel

    private func setupPanel() {
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 340))
        let hostingView = NSHostingView(rootView: ShelfView(store: store))
        panel.contentView = hostingView
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if let t = lastHideTime, Date().timeIntervalSince(t) > 10 {
            NotificationCenter.default.post(name: .resetShelfScroll, object: nil)
        }
        panel.showAtBottom()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self = self, self.panel.isVisible else { return }
            let screenPoint = NSEvent.mouseLocation
            if !self.panel.frame.contains(screenPoint) {
                self.hidePanel()
            }
        }
    }

    private func hidePanel() {
        lastHideTime = Date()
        ShelfPreviewController.shared.dismiss()
        panel.cancelOperation(nil)
        if let m = clickMonitor {
            NSEvent.removeMonitor(m)
            clickMonitor = nil
        }
    }

    @objc private func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Shelf Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func clearAll() {
        store.clearAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Login Item

    private func registerLoginItem() {
        try? SMAppService.mainApp.register()
    }

    // MARK: - Global Hotkey (Cmd+Shift+V)

    private func registerHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.togglePanel() }
                return noErr
            },
            1, &eventType, selfPtr, nil
        )

        let hotkeyID = EventHotKeyID(signature: 0x53484C46, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }
}
