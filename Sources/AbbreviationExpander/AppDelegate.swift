import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public var statusItem: NSStatusItem?
    public var statusMenu: NSMenu?
    public var isShowingMenu = false
    public var preferencesWindow: NSWindow?
    public var aboutWindow: NSWindow?
    public var viewModel: AppViewModel?

    public var lastCmdQTimestamp: Date?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

    public func setupMainMenu() {
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

        fileMenu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(closeItem)

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

    public func setupStatusMenu() {
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

    @objc public func handleStatusBarClick(_ sender: NSStatusBarButton) {
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

    public func menuDidClose(_ menu: NSMenu) {
        if menu == statusMenu {
            statusItem?.menu = nil
            isShowingMenu = false
        }
    }

    @objc public func importSnippetsAction() {
        openPreferencesWindow()
        viewModel?.importLibraryWithOpenPanel(targetWindow: preferencesWindow)
    }

    @objc public func exportSnippetsAction() {
        openPreferencesWindow()
        viewModel?.exportLibraryWithSavePanel(targetWindow: preferencesWindow)
    }

    public func getStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { rect in
            // Target height of 12.0 pt preserves optical balance matching macOS menu bar standard
            let targetH: CGFloat = 12.0
            let targetW: CGFloat = targetH / (476.0 / 668.0)
            let startX: CGFloat = (rect.width - targetW) / 2.0
            let startY: CGFloat = (rect.height - targetH) / 2.0

            func mapPoint(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                let nx = (x - 11.0) / 668.0
                let ny = (y - 94.0) / 476.0
                let px = startX + nx * targetW
                let py = startY + (1.0 - ny) * targetH
                return NSPoint(x: px, y: py)
            }

            let path1 = NSBezierPath()
            path1.move(to: mapPoint(339, 94))
            path1.line(to: mapPoint(471, 226))
            path1.line(to: mapPoint(471, 347))
            path1.line(to: mapPoint(339, 215))
            path1.line(to: mapPoint(131, 423))
            path1.line(to: mapPoint(11, 423))
            path1.close()

            let path2 = NSBezierPath()
            path2.move(to: mapPoint(679, 241))
            path2.line(to: mapPoint(679, 362))
            path2.line(to: mapPoint(471, 570))
            path2.line(to: mapPoint(339, 438))
            path2.line(to: mapPoint(339, 317))
            path2.line(to: mapPoint(471, 449))
            path2.close()

            NSColor.black.setFill()
            path1.fill()
            path2.fill()

            return true
        }
        icon.isTemplate = true
        return icon
    }

    @objc public func openPreferencesWindow() {
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

    @objc public func openAboutWindow() {
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
    @objc public func handleQuitMenuAction(_ sender: Any?) {
        let isKeyboardEvent = (NSApp.currentEvent?.type == .keyDown && NSApp.currentEvent?.modifierFlags.contains(.command) == true)
        if !isKeyboardEvent && (NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown) {
            // Direct mouse click on Quit menu item
            quitAppImmediately()
            return
        }
        handleQuitShortcut()
    }

    @objc public func handleQuitShortcut() {
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

    public func resetQuitTimestamp() {
        lastCmdQTimestamp = nil
    }

    @objc public func quitAppImmediately() {
        QuitHUDController.shared.dismiss()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Custom PreferencesWindow with Cmd+A & Cmd+Q Handling
public final class PreferencesWindow: NSWindow {
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
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
            if key == "w" {
                self.performClose(nil)
                return true
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
public struct AboutView: View {
    public init() {}

    public var body: some View {
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

                Text("Version \(AppConfig.version)")
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

public func loadAppIcon() -> NSImage? {
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
public struct QuitHUDView: View {
    public init() {}

    public var body: some View {
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

public final class QuitHUDController {
    public static let shared = QuitHUDController()

    public var panel: NSPanel?
    public var dismissWorkItem: DispatchWorkItem?

    public init() {}

    public func show(targetWindow: NSWindow? = nil) {
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

    public func dismiss() {
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
