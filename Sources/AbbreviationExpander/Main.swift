import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var viewModel: AppViewModel?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Proactively request Accessibility Permissions from macOS
        promptAccessibilityPermissions()

        let vm = AppViewModel()
        self.viewModel = vm

        setupStatusMenu()
        openPreferencesWindow()
    }

    private func promptAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !isTrusted {
            print("Notice: macOS Accessibility permission requested.")
        }
    }

    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let icon = getStatusBarIcon()
            icon.isTemplate = true
            button.image = icon
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "AbbrEx"
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open AbbrEx", action: #selector(openPreferencesWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func getStatusBarIcon() -> NSImage {
        let bundle = Bundle.main
        let candidateNames = ["status-bar-icon", "status-bar-iconTemplate", "StatusBarIcon", "StatusBarIconTemplate"]

        for name in candidateNames {
            if let url = bundle.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                return image
            }
            if let image = bundle.image(forResource: name) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                return image
            }
        }

        for relPath in ["Resources/status-bar-icon.png", "Resources/StatusBarIcon.png"] {
            if let image = NSImage(contentsOfFile: relPath) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                return image
            }
        }

        let fallback = NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }

    @objc private func openPreferencesWindow() {
        guard let vm = viewModel else { return }

        if preferencesWindow == nil {
            let prefView = PreferencesView(viewModel: vm)
            let hostingController = NSHostingController(rootView: prefView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "AbbrEx — Unified Library Engine"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            window.setFrameAutosaveName("PreferencesWindow")
            window.isReleasedWhenClosed = false
            self.preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
