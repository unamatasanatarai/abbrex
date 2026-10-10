import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public final class AppViewModel: ObservableObject {
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var libraryItems: [ExpansionPayload] = []

    public let stateMachine: StateMachine
    public let overlayPanel = OverlayPanel()
    public var eventMonitor: EventMonitor?
    public let storage: LibraryStorage

    private var showDebounceWorkItem: DispatchWorkItem?
    private var saveDebounceWorkItem: DispatchWorkItem?
    private var notificationObservers: [NSObjectProtocol] = []

    public init(storage: LibraryStorage = .shared) {
        self.storage = storage
        self.stateMachine = StateMachine()
        self.eventMonitor = EventMonitor(stateMachine: stateMachine)
        self.eventMonitor?.overlayPanel = self.overlayPanel
        self.libraryItems = Self.sortSnippets(storage.load())

        setupStateMachine()
        setupOverlayPanel()
        reloadTrie()
        checkAccessibilityPermissions()
        startMonitoring()
        setupAppActiveObserver()
        setupTerminationObserver()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupTerminationObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveLibrary(immediate: true)
        }
        notificationObservers.append(obs)
    }

    private func setupAppActiveObserver() {
        let obs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilityPermissions()
            self?.startMonitoring()
        }
        notificationObservers.append(obs)
    }

    public func reloadTrie() {
        stateMachine.loadItems(libraryItems)
    }

    public func startMonitoring() {
        eventMonitor?.start()
    }

    private func setupOverlayPanel() {
        overlayPanel.onCandidateSelected = { [weak self] index in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let expansionResult = self.stateMachine.processSelectionToExpand(index: index) {
                    TextReplacer.replace(prefixLength: expansionResult.prefixLength, evaluated: expansionResult.evaluated)
                    self.cancelAndDismissOverlay()
                }
            }
        }
    }

    public func setupStateMachine() {
        stateMachine.onStateChanged = { [weak self] state, matches, selectedIdx in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if state == .popupActive && !matches.isEmpty {
                    self.scheduleOverlayShow(matches: matches, selectedIndex: selectedIdx)
                } else {
                    self.cancelAndDismissOverlay()
                }
            }
        }
    }

    private func scheduleOverlayShow(matches: [ExpansionPayload], selectedIndex: Int) {
        showDebounceWorkItem?.cancel()

        // If overlay is ALREADY visible, update contents immediately
        if overlayPanel.isVisible {
            let caretRect = CaretTracker.getCaretScreenPosition(popupWidth: AppConfig.popupWidth, popupHeight: AppConfig.popupMaxHeight)
            overlayPanel.show(
                matches: matches,
                selectedIndex: selectedIndex,
                caretRect: caretRect
            )
            return
        }

        // If overlay is NOT yet visible, wait configured delay (e.g., 200ms) before showing popout
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.stateMachine.state == .popupActive && !self.stateMachine.activeMatches.isEmpty {
                let caretRect = CaretTracker.getCaretScreenPosition(popupWidth: AppConfig.popupWidth, popupHeight: AppConfig.popupMaxHeight)
                self.overlayPanel.show(
                    matches: matches,
                    selectedIndex: selectedIndex,
                    caretRect: caretRect
                )
            }
        }

        self.showDebounceWorkItem = workItem
        let delaySeconds = AppConfig.popupDelayMs / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: workItem)
    }

    private func cancelAndDismissOverlay() {
        showDebounceWorkItem?.cancel()
        showDebounceWorkItem = nil
        overlayPanel.dismiss()
    }

    public func checkAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        self.isAccessibilityGranted = trusted
    }

    public func openAccessibilitySettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public static func sortSnippets(_ items: [ExpansionPayload]) -> [ExpansionPayload] {
        return items.sorted { a, b in
            let aEmpty = a.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let bEmpty = b.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if aEmpty && !bEmpty { return true }
            if !aEmpty && bEmpty { return false }
            return a.prefix.localizedCaseInsensitiveCompare(b.prefix) == .orderedAscending
        }
    }

    public func sortLibraryItems() {
        self.libraryItems = Self.sortSnippets(libraryItems)
    }

    @discardableResult
    public func addItem(prefix: String, expansion: String) -> ExpansionPayload {
        let newItem = ExpansionPayload(prefix: prefix, expansion: expansion)
        libraryItems.append(newItem)
        sortLibraryItems()
        saveLibrary(immediate: true)
        reloadTrie()
        return newItem
    }

    public func updateItem(_ item: ExpansionPayload) {
        if let idx = libraryItems.firstIndex(where: { $0.id == item.id }) {
            libraryItems[idx] = item
            sortLibraryItems()
            saveLibrary(immediate: false)
            reloadTrie()
        }
    }

    public func deleteItem(_ item: ExpansionPayload) {
        libraryItems.removeAll(where: { $0.id == item.id })
        saveLibrary(immediate: true)
        reloadTrie()
    }

    public func saveLibrary(immediate: Bool = false) {
        saveDebounceWorkItem?.cancel()
        if immediate {
            do {
                try storage.save(items: libraryItems)
            } catch {
                print("Failed to save abbreviation library: \(error)")
            }
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            do {
                try self.storage.save(items: self.libraryItems)
            } catch {
                print("Failed to save abbreviation library: \(error)")
            }
        }
        self.saveDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    // MARK: - JSON Import & Export
    public func exportLibraryWithSavePanel(targetWindow: NSWindow? = nil) {
        let panel = NSSavePanel()
        panel.title = "Export Snippets"
        panel.nameFieldStringValue = "abbrex-library.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.prompt = "Export"

        let onComplete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let nonEmpties = self.libraryItems.filter {
                    !$0.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !$0.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                let data = try encoder.encode(nonEmpties)
                try data.write(to: url, options: .atomic)
            } catch {
                print("Failed to export snippets: \(error)")
            }
        }

        if let window = targetWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: onComplete)
        } else {
            let response = panel.runModal()
            onComplete(response)
        }
    }

    public func importLibraryWithOpenPanel(targetWindow: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Import Snippets"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"

        let onComplete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            guard let data = try? Data(contentsOf: url) else { return }

            let decoder = JSONDecoder()

            // 1. Try native ExpansionPayload array
            if let items = try? decoder.decode([ExpansionPayload].self, from: data) {
                let valid = items.filter {
                    !$0.prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !$0.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if !valid.isEmpty {
                    self.replaceLibrary(with: valid)
                    return
                }
            }

            // 2. Try generic array with optional fields (no id needed)
            struct SnippetItem: Decodable {
                let prefix: String?
                let expansion: String?
                let tags: [String]?
            }
            if let snippetItems = try? decoder.decode([SnippetItem].self, from: data) {
                let payloads = snippetItems.compactMap { item -> ExpansionPayload? in
                    guard let p = item.prefix, let e = item.expansion else { return nil }
                    let cleanP = p.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanE = e.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanP.isEmpty || !cleanE.isEmpty else { return nil }
                    return ExpansionPayload(prefix: p, expansion: e, tags: item.tags)
                }
                if !payloads.isEmpty {
                    self.replaceLibrary(with: payloads)
                    return
                }
            }

            // 3. Try key-value dictionary { ":prefix": "expansion" }
            if let dict = try? decoder.decode([String: String].self, from: data) {
                let payloads = dict.compactMap { (prefix, expansion) -> ExpansionPayload? in
                    let cleanP = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanE = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanP.isEmpty || !cleanE.isEmpty else { return nil }
                    return ExpansionPayload(prefix: prefix, expansion: expansion)
                }.sorted(by: { $0.prefix < $1.prefix })
                if !payloads.isEmpty {
                    self.replaceLibrary(with: payloads)
                    return
                }
            }
        }

        if let window = targetWindow ?? NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: onComplete)
        } else {
            let response = panel.runModal()
            onComplete(response)
        }
    }

    public func replaceLibrary(with items: [ExpansionPayload]) {
        self.libraryItems = Self.sortSnippets(items)
        saveLibrary(immediate: true)
        reloadTrie()
    }
}
