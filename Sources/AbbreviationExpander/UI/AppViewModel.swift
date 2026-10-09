import Foundation
import SwiftUI
import AppKit

public final class AppViewModel: ObservableObject {
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var libraryItems: [ExpansionPayload] = []

    public let stateMachine: StateMachine
    public let overlayPanel = OverlayPanel()
    public var eventMonitor: EventMonitor?
    public let storage: LibraryStorage

    private var showDebounceWorkItem: DispatchWorkItem?
    private var saveDebounceWorkItem: DispatchWorkItem?

    public init(storage: LibraryStorage = .shared) {
        self.storage = storage
        self.stateMachine = StateMachine()
        self.eventMonitor = EventMonitor(stateMachine: stateMachine)
        self.eventMonitor?.overlayPanel = self.overlayPanel
        self.libraryItems = storage.load()

        setupStateMachine()
        setupOverlayPanel()
        reloadTrie()
        checkAccessibilityPermissions()
        startMonitoring()
        setupAppActiveObserver()
        setupTerminationObserver()
    }

    private func setupTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveLibrary(immediate: true)
        }
    }

    private func setupAppActiveObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilityPermissions()
            self?.startMonitoring()
        }
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

    @discardableResult
    public func addItem(prefix: String, expansion: String) -> ExpansionPayload {
        let newItem = ExpansionPayload(prefix: prefix, expansion: expansion)
        libraryItems.insert(newItem, at: 0)
        saveLibrary(immediate: true)
        reloadTrie()
        return newItem
    }

    public func updateItem(_ item: ExpansionPayload) {
        if let idx = libraryItems.firstIndex(where: { $0.id == item.id }) {
            libraryItems[idx] = item
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
}
