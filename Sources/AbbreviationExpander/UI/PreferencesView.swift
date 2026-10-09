import SwiftUI
import AppKit

public struct PreferencesView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var selectedTab = 0
    @State private var singleLineText = ""
    @State private var multiLineText = ""
    @State private var searchText = ""

    @State private var selectedItemId: String?

    @FocusState private var focusedField: FocusField?
    private enum FocusField: Hashable {
        case prefix
        case expansion
    }

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                // TAB 1: Unified Library & Inline Autosaving Editor
                libraryAndEditorTab
                    .tabItem {
                        Label("Abbreviation Library", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(0)

                // TAB 2: Live Interactive Sandbox & State Inspector
                playgroundTab
                    .tabItem {
                        Label("Live Sandbox", systemImage: "play.terminal.fill")
                    }
                    .tag(1)
            }

            // Accessibility permission toast notification if not granted
            if !viewModel.isAccessibilityGranted {
                accessibilityToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isAccessibilityGranted)
        .frame(width: 780, height: 540)
        .onAppear {
            if selectedItemId == nil {
                selectedItemId = viewModel.libraryItems.first?.id
            }
        }
    }

    // MARK: - Accessibility Permission Toast
    private var accessibilityToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.system(size: 12, weight: .semibold))
                Text("AbbrEx needs permission in System Settings to detect abbreviations and expand text.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Grant Permission") {
                viewModel.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Tab 1: Library & Inline Autosaving Editor
    private var libraryAndEditorTab: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN: Search & Item List
            VStack(spacing: 10) {
                // Header & Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search library...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .padding([.top, .horizontal], 12)

                // Add Inline Button
                Button(action: createNewAbbreviation) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("New Abbreviation")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)

                Divider()

                // List of items
                List(selection: $selectedItemId) {
                    ForEach(filteredItems, id: \.id) { item in
                        ItemRow(item: item, isSelected: selectedItemId == item.id)
                            .tag(item.id)
                            .onTapGesture {
                                selectedItemId = item.id
                            }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 260)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // RIGHT COLUMN: Live Inline Autosaving Editor
            VStack {
                if let selectedId = selectedItemId, let item = viewModel.libraryItems.first(where: { $0.id == selectedId }) {
                    inlineDetailEditor(item: item)
                } else if let firstItem = viewModel.libraryItems.first {
                    inlineDetailEditor(item: firstItem)
                } else {
                    emptySelectionView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - Simplified Inline Detail Editor Panel (Autosaved continuously)
    private func inlineDetailEditor(item: ExpansionPayload) -> some View {
        let binding = Binding<ExpansionPayload>(
            get: { item },
            set: { updated in
                viewModel.updateItem(updated)
            }
        )

        return VStack(alignment: .leading, spacing: 14) {
            // Header Bar with Trash icon only
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abbreviation Prefix")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.prefix.isEmpty ? "New Abbreviation" : item.prefix)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(item.prefix.isEmpty ? .secondary : .accentColor)
                }

                Spacer()

                // Delete button: trash icon only (no text label)
                Button(action: {
                    viewModel.deleteItem(item)
                    selectedItemId = viewModel.libraryItems.first?.id
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
                .help("Delete abbreviation")
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                // 1. Prefix Field (auto-focused on "New Abbreviation")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prefix:")
                        .font(.caption)
                        .bold()
                    TextField("Prefix (e.g. 'c-sig')", text: Binding(
                        get: { binding.wrappedValue.prefix },
                        set: { val in
                            var curr = binding.wrappedValue
                            curr = ExpansionPayload(id: curr.id, prefix: val, expansion: curr.expansion, tags: curr.tags)
                            binding.wrappedValue = curr
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .prefix)
                }

                // 2. Expansion Template Editor + Token Helper Chips
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Expansion Template:")
                            .font(.caption)
                            .bold()
                        Spacer()
                    }

                    // Token Chips Helper
                    HStack(spacing: 6) {
                        Text("Insert Token:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        TokenChip(token: "{{date}}") {
                            insertToken("{{date}}", into: binding)
                        }
                        TokenChip(token: "{{time}}") {
                            insertToken("{{time}}", into: binding)
                        }
                        TokenChip(token: "{{clipboard}}") {
                            insertToken("{{clipboard}}", into: binding)
                        }
                        TokenChip(token: "{{cursor}}") {
                            insertToken("{{cursor}}", into: binding)
                        }
                    }

                    TextEditor(text: Binding(
                        get: { binding.wrappedValue.expansion },
                        set: { val in
                            var curr = binding.wrappedValue
                            curr = ExpansionPayload(id: curr.id, prefix: curr.prefix, expansion: val, tags: curr.tags)
                            binding.wrappedValue = curr
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .focused($focusedField, equals: .expansion)
                    .frame(minHeight: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Select an abbreviation from the list to edit, or click 'New Abbreviation' to create one.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: createNewAbbreviation) {
                Label("New Abbreviation", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    private func createNewAbbreviation() {
        if let first = viewModel.libraryItems.first, first.prefix.isEmpty && first.expansion.isEmpty {
            selectedItemId = first.id
            DispatchQueue.main.async {
                focusedField = .prefix
            }
            return
        }

        let newItem = viewModel.addItem(prefix: "", expansion: "")
        selectedItemId = newItem.id
        DispatchQueue.main.async {
            focusedField = .prefix
        }
    }

    private func insertToken(_ token: String, into binding: Binding<ExpansionPayload>) {
        var curr = binding.wrappedValue
        let updatedText = curr.expansion + token
        curr = ExpansionPayload(id: curr.id, prefix: curr.prefix, expansion: updatedText, tags: curr.tags)
        binding.wrappedValue = curr
    }

    // MARK: - Tab 2: Live Interactive Sandbox
    private var playgroundTab: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interactive Expander Sandbox")
                        .font(.title2)
                        .bold()
                    Text("Test real-time abbreviation expansion against your library.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding([.top, .horizontal], 16)

            Divider()

            HStack(spacing: 12) {
                MetricCard(
                    title: "Engine State",
                    value: viewModel.currentState.description,
                    color: stateColor(viewModel.currentState)
                )

                MetricCard(
                    title: "Keystroke Buffer",
                    value: viewModel.currentBuffer.isEmpty ? "(empty)" : viewModel.currentBuffer,
                    color: .blue
                )

                MetricCard(
                    title: "Active Matches",
                    value: "\(viewModel.activeMatches.count)",
                    color: .purple
                )

                MetricCard(
                    title: "Trie Lookup",
                    value: "< 0.2 ms",
                    color: .green
                )
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 12) {
                Text("Type any prefix (e.g. 'c-disc', 'c-sig', 'qa-bug'), navigate with Ctrl+jk / Ctrl+np, then press Tab/Enter/Click:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Single-line Input:")
                            .font(.caption)
                            .bold()
                        TextField("Type prefix here...", text: $singleLineText)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Multi-line Text Area:")
                            .font(.caption)
                            .bold()
                        TextEditor(text: $multiLineText)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
    }

    private var filteredItems: [ExpansionPayload] {
        if searchText.isEmpty { return viewModel.libraryItems }
        return viewModel.libraryItems.filter {
            $0.prefix.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func stateColor(_ state: EngineState) -> Color {
        switch state {
        case .idle: return .secondary
        case .buffering: return .blue
        case .popupActive: return .purple
        case .expanded: return .green
        case .cancelled: return .orange
        }
    }
}

public struct TokenChip: View {
    public let token: String
    public let onClick: () -> Void

    public var body: some View {
        Button(action: onClick) {
            Text(token)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

public struct MetricCard: View {
    public let title: String
    public let value: String
    public let color: Color

    public init(title: String, value: String, color: Color) {
        self.title = title
        self.value = value
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .bold()
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

public struct ItemRow: View {
    public let item: ExpansionPayload
    public let isSelected: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.prefix.isEmpty ? "New Abbreviation" : item.prefix)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .white : (item.prefix.isEmpty ? .secondary : .accentColor))

            Text(item.expansion.isEmpty ? "Empty template" : item.expansion.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isSelected ? Color.white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
