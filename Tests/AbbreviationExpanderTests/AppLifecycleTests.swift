import Foundation
import SwiftUI
import AppKit

public struct AppLifecycleTests {
    @MainActor
    public static func run(testRunner: TestRunner) {

        testRunner("AppLifecycle - AppDelegate, Menus & Windows") {
            let delegate = AppDelegate()
            assert(delegate.preferencesWindow == nil, "Initial preferencesWindow should be nil")
            assert(delegate.aboutWindow == nil, "Initial aboutWindow should be nil")

            // Setup main menu & status menu
            delegate.setupMainMenu()
            assert(NSApp.mainMenu != nil, "NSApp.mainMenu should not be nil")

            delegate.setupStatusMenu()
            assert(delegate.statusItem != nil, "statusItem should be initialized")

            // Status bar icon
            let icon = delegate.getStatusBarIcon()
            assert(icon.isTemplate, "Status bar icon should be a template image")

            // Menu did close
            delegate.menuDidClose(delegate.statusMenu ?? NSMenu())
            assert(!delegate.isShowingMenu, "isShowingMenu should be false after menuDidClose")

            // Open About Window
            delegate.openAboutWindow()
            assert(delegate.aboutWindow != nil, "aboutWindow should be created")
            assert(delegate.aboutWindow?.title == "About AbbrEx", "About window title mismatch")

            // Open Preferences Window
            delegate.viewModel = AppViewModel()
            delegate.openPreferencesWindow()
            assert(delegate.preferencesWindow != nil, "preferencesWindow should be created")
            assert(delegate.preferencesWindow?.title == "AbbrEx", "Preferences window title mismatch")

            // Double-tap Cmd+Q guard:
            // First tap shows HUD prompt
            delegate.resetQuitTimestamp()
            assert(delegate.lastCmdQTimestamp == nil, "lastCmdQTimestamp should be nil")
            delegate.handleQuitShortcut()
            assert(delegate.lastCmdQTimestamp != nil, "lastCmdQTimestamp should be recorded on first tap")

            // Reset timestamp
            delegate.resetQuitTimestamp()
            assert(delegate.lastCmdQTimestamp == nil, "lastCmdQTimestamp should be nil after reset")

            // PreferencesWindow Key Equivalents: Cmd+A, Cmd+W, Cmd+Q
            let window = PreferencesWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            let cmdA = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0x00)!
            _ = window.performKeyEquivalent(with: cmdA)

            let cmdW = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 0x0D)!
            assert(window.performKeyEquivalent(with: cmdW), "Cmd+W on PreferencesWindow should be handled")

            let cmdQ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 0x0C)!
            _ = window.performKeyEquivalent(with: cmdQ)

            // AboutView & QuitHUDView rendering
            let aboutView = AboutView()
            _ = aboutView.body

            let quitHUDView = QuitHUDView()
            _ = quitHUDView.body

            // QuitHUDController
            let hud = QuitHUDController()
            hud.show(targetWindow: window)
            assert(hud.panel != nil, "QuitHUDController panel should be created")
            hud.dismiss()

            // loadAppIcon
            _ = loadAppIcon()
        }
    }
}
