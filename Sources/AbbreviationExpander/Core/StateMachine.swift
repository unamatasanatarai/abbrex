import Foundation

public enum NavigationDirection {
    case up
    case down
}

public struct ExpansionResult {
    public let payload: ExpansionPayload
    public let prefixLength: Int
    public let evaluated: EvaluatedTemplate

    public init(payload: ExpansionPayload, prefixLength: Int, evaluated: EvaluatedTemplate) {
        self.payload = payload
        self.prefixLength = prefixLength
        self.evaluated = evaluated
    }
}

/// Central state machine managing transitions across IDLE, BUFFERING, POPUP_ACTIVE, EXPANDED, CANCELLED.
public final class StateMachine {
    public private(set) var state: EngineState = .idle
    public private(set) var buffer: String = ""
    public private(set) var activeMatches: [ExpansionPayload] = []
    public private(set) var selectedIndex: Int = 0

    public let trie: AbbreviationTrie

    public var onStateChanged: ((EngineState, [ExpansionPayload], Int) -> Void)?

    public init(trie: AbbreviationTrie = AbbreviationTrie()) {
        self.trie = trie
    }

    /// Loads items into the internal Trie structure.
    public func loadItems(_ items: [ExpansionPayload]) {
        trie.clear()
        for item in items {
            trie.insert(prefix: item.prefix, payload: item)
        }
        reset()
    }

    /// Processes a printable key input character.
    @discardableResult
    public func processCharacter(_ char: Character) -> EngineState {
        // Non-printable or whitespace characters trigger cancellation
        if char.isWhitespace || char.isNewline {
            reset(state: .idle)
            return state
        }

        buffer.append(char)

        // Fast-path: If the buffer already yielded 0 matches, any extension will also have 0 matches in a prefix tree.
        if state == .buffering && activeMatches.isEmpty {
            return state
        }

        updateMatchesAndState()
        return state
    }

    /// Processes backspace keystroke.
    @discardableResult
    public func processBackspace() -> EngineState {
        guard !buffer.isEmpty else {
            reset(state: .idle)
            return state
        }
        buffer.removeLast()
        if buffer.isEmpty {
            reset(state: .idle)
        } else {
            updateMatchesAndState()
        }
        return state
    }

    /// Navigates selection up or down within active popup candidates.
    public func navigateSelection(direction: NavigationDirection) {
        guard state == .popupActive, !activeMatches.isEmpty else { return }

        switch direction {
        case .up:
            selectedIndex = (selectedIndex - 1 + activeMatches.count) % activeMatches.count
        case .down:
            selectedIndex = (selectedIndex + 1) % activeMatches.count
        }

        notifyStateChange()
    }

    /// Expands candidate at specific index (or currently selected index if index is nil).
    /// Triggered by Tab, Enter, or Mouse click.
    public func processSelectionToExpand(index: Int? = nil, customDate: Date? = nil, customClipboard: String? = nil) -> ExpansionResult? {
        guard state == .popupActive, !activeMatches.isEmpty else {
            return nil
        }

        let targetIndex = index ?? selectedIndex
        guard targetIndex >= 0 && targetIndex < activeMatches.count else { return nil }

        let selectedMatch = activeMatches[targetIndex]
        let prefixLen = buffer.count
        let evaluated = TemplateEngine.evaluate(template: selectedMatch.expansion, customDate: customDate, customClipboard: customClipboard)

        state = .expanded
        reset(state: .idle)

        return ExpansionResult(payload: selectedMatch, prefixLength: prefixLen, evaluated: evaluated)
    }

    /// Cancels active buffering / popup state instantly.
    public func cancel() {
        reset(state: .cancelled)
    }

    /// Resets buffer and sets target state.
    public func reset(state targetState: EngineState = .idle) {
        if state == targetState && buffer.isEmpty && activeMatches.isEmpty {
            return
        }
        buffer = ""
        activeMatches = []
        selectedIndex = 0
        state = targetState
        notifyStateChange()
    }

    private func updateMatchesAndState() {
        activeMatches = trie.searchPrefix(buffer)
        if !activeMatches.isEmpty {
            state = .popupActive
            if selectedIndex >= activeMatches.count {
                selectedIndex = 0
            }
        } else {
            state = buffer.isEmpty ? .idle : .buffering
            selectedIndex = 0
        }
        notifyStateChange()
    }

    private func notifyStateChange() {
        onStateChanged?(state, activeMatches, selectedIndex)
    }
}
