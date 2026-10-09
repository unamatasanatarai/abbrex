import SwiftUI
import AppKit
import Combine

public struct PreferencesView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var searchText = ""
    @State private var selectedItemId: String?

    // Stashed deleted item for undo functionality
    @State private var recentlyDeletedItem: (item: ExpansionPayload, index: Int)?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Permission banner: in layout flow, smoothly pushing other elements down
            if !viewModel.isAccessibilityGranted {
                permissionBanner
                Divider()
            }

            // Minimalist master-detail split view
            HSplitView {
                sidebarView
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

                editorView
                    .frame(minWidth: 360, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 400, idealHeight: 480)
        .onAppear {
            if selectedItemId == nil {
                selectedItemId = viewModel.libraryItems.first?.id
            }
        }
        .onDisappear {
            // When the window is closed, undo gets dissolved
            recentlyDeletedItem = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            recentlyDeletedItem = nil
        }
    }

    // MARK: - Permission Banner (Pushes content down, never overlays)
    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))

            Text("Accessibility permission required to expand abbreviations")
                .font(.system(size: 12))
                .foregroundColor(.primary)

            Spacer()

            Button("Enable") {
                viewModel.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isAccessibilityGranted)
    }

    // MARK: - Sidebar (Search, Add, List, Undo / Restore Delete)
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Header: Single-line search input + single '+' button
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))

                    MacSingleLineTextField(
                        placeholder: "Search...",
                        text: $searchText,
                        font: .systemFont(ofSize: 12)
                    )
                    .frame(height: 20)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.7))
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Button(action: createNewAbbreviation) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .help("New abbreviation")
            }
            .padding(10)

            Divider()

            // List of abbreviations
            List(selection: $selectedItemId) {
                ForEach(filteredItems, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.prefix.isEmpty ? "New Abbreviation" : item.prefix)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(item.prefix.isEmpty ? .secondary : (selectedItemId == item.id ? .white : .accentColor))

                        Text(item.expansion.isEmpty ? "Empty template" : item.expansion.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(selectedItemId == item.id ? Color.white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(item.id)
                }
            }
            .listStyle(.sidebar)

            // Restore deleted snippet bar (persists across navigation and editing; dissolved on window close)
            if let deleted = recentlyDeletedItem {
                Divider()
                HStack {
                    Button(action: undoDelete) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 10, weight: .semibold))
                            Text(restoreButtonTitle(for: deleted.item))
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Restore deleted abbreviation")

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .transition(.opacity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Editor (Isolated detail view to prevent typing cursor jumps)
    @ViewBuilder
    private var editorView: some View {
        if let selectedId = selectedItemId, let item = viewModel.libraryItems.first(where: { $0.id == selectedId }) {
            ItemEditorView(
                item: item,
                isNew: item.prefix.isEmpty && item.expansion.isEmpty,
                onUpdate: { updated in
                    viewModel.updateItem(updated)
                },
                onDelete: {
                    deleteItem(item)
                }
            )
            .id(item.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No Abbreviation Selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private func createNewAbbreviation() {
        if let first = viewModel.libraryItems.first, first.prefix.isEmpty && first.expansion.isEmpty {
            selectedItemId = first.id
            return
        }

        let newItem = viewModel.addItem(prefix: "", expansion: "")
        selectedItemId = newItem.id
    }

    private func deleteItem(_ item: ExpansionPayload) {
        if let idx = viewModel.libraryItems.firstIndex(where: { $0.id == item.id }) {
            // Replace any previous undo with the newly deleted item
            recentlyDeletedItem = (item: item, index: idx)
            viewModel.deleteItem(item)
            selectedItemId = viewModel.libraryItems.first?.id
        }
    }

    private func undoDelete() {
        guard let deleted = recentlyDeletedItem else { return }
        let restoreIndex = min(deleted.index, viewModel.libraryItems.count)
        viewModel.libraryItems.insert(deleted.item, at: restoreIndex)
        viewModel.saveLibrary(immediate: true)
        viewModel.reloadTrie()
        selectedItemId = deleted.item.id
        recentlyDeletedItem = nil
    }

    private func restoreButtonTitle(for item: ExpansionPayload) -> String {
        let rawTitle: String
        let trimmedPrefix = item.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpansion = item.expansion.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")

        if !trimmedPrefix.isEmpty {
            rawTitle = trimmedPrefix
        } else if !trimmedExpansion.isEmpty {
            rawTitle = trimmedExpansion
        } else {
            rawTitle = "snippet"
        }

        let titleSnippet: String
        if rawTitle.count > 10 {
            titleSnippet = String(rawTitle.prefix(10)) + "…"
        } else {
            titleSnippet = rawTitle
        }
        return "restore \(titleSnippet)"
    }

    private var filteredItems: [ExpansionPayload] {
        if searchText.isEmpty { return viewModel.libraryItems }
        return viewModel.libraryItems.filter {
            $0.prefix.localizedCaseInsensitiveContains(searchText) ||
            $0.expansion.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Isolated Item Editor View
struct ItemEditorView: View {
    let item: ExpansionPayload
    let isNew: Bool
    let onUpdate: (ExpansionPayload) -> Void
    let onDelete: () -> Void

    @State private var prefix: String
    @State private var expansion: String

    init(
        item: ExpansionPayload,
        isNew: Bool,
        onUpdate: @escaping (ExpansionPayload) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isNew = isNew
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _prefix = State(initialValue: item.prefix)
        _expansion = State(initialValue: item.expansion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Prefix input + single trash button
            HStack(spacing: 10) {
                Text("Prefix:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                MacSingleLineTextField(
                    placeholder: "e.g. :sig",
                    text: $prefix,
                    font: .systemFont(ofSize: 14),
                    isMonospaced: true,
                    isAutoFocused: isNew
                )
                .frame(height: 22)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(5)
                .help("Delete abbreviation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Expansion multiline textarea: native NSTextView ensuring no cursor jumps
            MacTextEditor(
                text: $expansion,
                font: .monospacedSystemFont(ofSize: 13, weight: .regular)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Variables hint (non-interactive, minimal)
            HStack {
                Text("Variables: {{date}}  {{time}}  {{clipboard}}")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.25))
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: prefix) { newPrefix in
            onUpdate(ExpansionPayload(id: item.id, prefix: newPrefix, expansion: expansion, tags: item.tags))
        }
        .onChange(of: expansion) { newExpansion in
            onUpdate(ExpansionPayload(id: item.id, prefix: prefix, expansion: newExpansion, tags: item.tags))
        }
    }
}

// MARK: - MacSingleLineTextField (Single-line input, no multiline wrapping, handles Cmd+A)
struct MacSingleLineTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var font: NSFont
    var isMonospaced: Bool
    var isAutoFocused: Bool
    var onCommit: (() -> Void)?

    init(
        placeholder: String,
        text: Binding<String>,
        font: NSFont = .systemFont(ofSize: 12),
        isMonospaced: Bool = false,
        isAutoFocused: Bool = false,
        onCommit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.isMonospaced = isMonospaced
        self.isAutoFocused = isAutoFocused
        self.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = CustomNSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.font = isMonospaced ? .monospacedSystemFont(ofSize: font.pointSize, weight: .bold) : font
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isBezeled = false
        textField.focusRingType = .none
        textField.maximumNumberOfLines = 1
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.lineBreakMode = .byClipping
        textField.delegate = context.coordinator
        textField.shouldAutoFocusOnAppear = isAutoFocused

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacSingleLineTextField

        init(_ parent: MacSingleLineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            var val = textField.stringValue
            if val.contains("\n") || val.contains("\r") {
                val = val.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                textField.stringValue = val
            }
            if parent.text != val {
                parent.text = val
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit?()
                return true // Swallow newline to keep strictly single-line
            }
            if commandSelector == #selector(NSText.selectAll(_:)) {
                textView.selectAll(nil)
                return true
            }
            return false
        }
    }
}

final class CustomNSTextField: NSTextField {
    var shouldAutoFocusOnAppear: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if shouldAutoFocusOnAppear, let window = self.window {
            DispatchQueue.main.async {
                window.makeFirstResponder(self)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "a" {
                if let editor = self.currentEditor() {
                    editor.selectAll(nil)
                } else {
                    self.selectText(nil)
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - MacTextEditor (Regular textarea, handles Cmd+A, never jumps cursor to end on typing)
struct MacTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var isEditable: Bool = true

    init(
        text: Binding<String>,
        font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
        isEditable: Bool = true
    ) {
        self._text = text
        self.font = font
        self.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = MacNSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        textView.font = font
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = text
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // CRITICAL: Only update if the string has changed externally!
        // When the user is typing, textView.string is ALREADY equal to text.
        // Therefore, we do NOT assign textView.string, which prevents the cursor from jumping to the end!
        if textView.string != text {
            let prevRange = textView.selectedRange()
            textView.string = text
            if prevRange.location + prevRange.length <= text.utf16.count {
                textView.setSelectedRange(prevRange)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextEditor
        weak var textView: NSTextView?

        init(_ parent: MacTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let currentString = textView.string
            if parent.text != currentString {
                parent.text = currentString
            }
        }
    }
}

final class MacNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "a" {
                self.selectAll(nil)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
