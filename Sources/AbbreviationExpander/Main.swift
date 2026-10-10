import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var isShowingMenu = false
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var viewModel: AppViewModel?

    private var lastCmdQTimestamp: Date?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Set high-resolution application icon
        if let icon = loadAppIcon() {
            NSApp.applicationIconImage = icon
        }

        let vm = AppViewModel()
        self.viewModel = vm

        setupMainMenu()
        setupStatusMenu()

        // Only show window on launch if accessibility permissions are not yet granted
        if !vm.isAccessibilityGranted {
            openPreferencesWindow()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem(title: "AbbrEx", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "AbbrEx")
        
        let aboutItem = NSMenuItem(title: "About AbbrEx", action: #selector(openAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit AbbrEx", action: #selector(handleQuitMenuAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu (Import and Export)
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")

        let importItem = NSMenuItem(title: "Import Snippets...", action: #selector(importSnippetsAction), keyEquivalent: "i")
        importItem.target = self
        fileMenu.addItem(importItem)

        let exportItem = NSMenuItem(title: "Export Snippets...", action: #selector(exportSnippetsAction), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(exportItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu (Crucial for Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z across all inputs)
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }


    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let icon = getStatusBarIcon()
        icon.isTemplate = true
        button.image = icon
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.toolTip = "AbbrEx"

        button.target = self
        button.action = #selector(handleStatusBarClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.delegate = self

        let openItem = NSMenuItem(title: "Open AbbrEx", action: #selector(openPreferencesWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let importItem = NSMenuItem(title: "Import Snippets...", action: #selector(importSnippetsAction), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        let exportItem = NSMenuItem(title: "Export Snippets...", action: #selector(exportSnippetsAction), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(handleQuitMenuAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusMenu = menu
        // statusItem?.menu is intentionally left nil to allow distinguishing left vs right click
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard !isShowingMenu else { return }

        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp ||
            (event?.modifierFlags.contains(.control) == true && (event?.type == .leftMouseUp || event?.type == .leftMouseDown))

        if isRightClick {
            isShowingMenu = true
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
        } else {
            openPreferencesWindow()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu == statusMenu {
            statusItem?.menu = nil
            isShowingMenu = false
        }
    }

    @objc func importSnippetsAction() {
        openPreferencesWindow()
        viewModel?.importLibraryWithOpenPanel(targetWindow: preferencesWindow)
    }

    @objc func exportSnippetsAction() {
        openPreferencesWindow()
        viewModel?.exportLibraryWithSavePanel(targetWindow: preferencesWindow)
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

            let window = PreferencesWindow(contentViewController: hostingController)
            window.title = "AbbrEx"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            window.setFrameAutosaveName("PreferencesWindow")
            window.isReleasedWhenClosed = false
            self.preferencesWindow = window
        }

        if preferencesWindow?.isMiniaturized == true {
            preferencesWindow?.deminiaturize(nil)
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openAboutWindow() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "About AbbrEx"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.aboutWindow = window
        }

        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Double-tap Cmd+Q Handling
    @objc func handleQuitMenuAction(_ sender: Any?) {
        let isKeyboardEvent = (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.modifierFlags.contains(.command) == true)
        if !isKeyboardEvent && (NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown) {
            // Direct mouse click on Quit menu item
            quitAppImmediately()
            return
        }
        handleQuitShortcut()
    }

    @objc func handleQuitShortcut() {
        let now = Date()
        if let last = lastCmdQTimestamp, now.timeIntervalSince(last) < 1.5 {
            // Second tap within 1.5s -> Quit!
            QuitHUDController.shared.dismiss()
            NSApplication.shared.terminate(nil)
            return
        }

        // First tap -> Record time & show HUD prompt
        lastCmdQTimestamp = now
        QuitHUDController.shared.show(targetWindow: preferencesWindow)
    }

    func resetQuitTimestamp() {
        lastCmdQTimestamp = nil
    }

    @objc func quitAppImmediately() {
        QuitHUDController.shared.dismiss()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Custom PreferencesWindow with Cmd+A & Cmd+Q Handling
final class PreferencesWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "a" {
                if let firstResponder = self.firstResponder {
                    if firstResponder.responds(to: #selector(NSText.selectAll(_:))) {
                        firstResponder.perform(#selector(NSText.selectAll(_:)), with: nil)
                        return true
                    }
                }
            }
            if key == "q" {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.handleQuitShortcut()
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - About Screen View
struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let icon = loadAppIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
            } else {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 4) {
                Text("AbbrEx")
                    .font(.system(size: 20, weight: .bold))

                Text("Version 1.0.0")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text("Fast, native abbreviation & snippet expander for macOS.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 20)

            Link(destination: URL(string: "https://github.com/unamatasanatarai/abbrex")!) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                    Text("https://github.com/unamatasanatarai/abbrex")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Text("Copyright © 2026. All rights reserved.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(24)
        .frame(width: 320)
    }
}

func loadAppIcon() -> NSImage? {
    let bundle = Bundle.main
    for ext in ["png", "icns"] {
        if let url = bundle.url(forResource: "AppIcon", withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }
    }
    if let img = NSImage(named: NSImage.Name("AppIcon")) {
        return img
    }
    for relPath in ["Resources/AppIcon.png", "Resources/AppIcon.icns"] {
        if let img = NSImage(contentsOfFile: relPath) {
            return img
        }
    }
    return NSApp.applicationIconImage
}

// MARK: - Double-tap Cmd+Q HUD Prompt
struct QuitHUDView: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Text("⌘")
                    .font(.system(size: 13, weight: .bold))
                Text("Q")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.2))
            .cornerRadius(5)

            Text("Press ⌘Q again to quit")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

final class QuitHUDController {
    static let shared = QuitHUDController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func show(targetWindow: NSWindow? = nil) {
        dismissWorkItem?.cancel()

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 250, height: 46),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .transient]

            let hostingView = NSHostingView(rootView: QuitHUDView())
            p.contentView = hostingView
            self.panel = p
        }

        guard let p = panel else { return }

        // Position HUD centered near bottom of active window or main screen
        if let window = targetWindow, window.isVisible {
            let windowFrame = window.frame
            let x = windowFrame.midX - (p.frame.width / 2)
            let y = windowFrame.minY + 36
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - (p.frame.width / 2)
            let y = screenFrame.minY + 60
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.alphaValue = 0
        p.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            p.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.resetQuitTimestamp()
            }
        }
        self.dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            p.animator().alphaValue = 0.0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }
}
