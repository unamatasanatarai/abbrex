import SwiftUI
import AppKit

/// Observable View Model backing CandidateListView for zero-allocation updates.
public final class CandidateViewModel: ObservableObject {
    @Published public var matches: [ExpansionPayload] = []
    @Published public var selectedIndex: Int? = nil

    public init(matches: [ExpansionPayload] = [], selectedIndex: Int? = nil) {
        self.matches = matches
        self.selectedIndex = selectedIndex
    }
}

/// Floating accessible overlay list view displaying candidate abbreviation matches.
public struct CandidateListView: View {
    @ObservedObject var viewModel: CandidateViewModel
    public var onSelectCandidate: ((Int) -> Void)?

    public init(viewModel: CandidateViewModel, onSelectCandidate: ((Int) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSelectCandidate = onSelectCandidate
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(Array(viewModel.matches.enumerated()), id: \.element.id) { index, match in
                        CandidateRow(
                            match: match,
                            isSelected: viewModel.selectedIndex != nil && index == viewModel.selectedIndex
                        ) {
                            onSelectCandidate?(index)
                        }
                        .id(match.id)
                    }
                }
                .padding(3)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                if let newIndex = newIndex, newIndex >= 0 && newIndex < viewModel.matches.count {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(viewModel.matches[newIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: AppConfig.popupWidth, height: min(CGFloat(viewModel.matches.count) * 26 + 6, AppConfig.popupMaxHeight))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Abbreviation candidate list")
    }
}

public struct CandidateRow: View {
    public let match: ExpansionPayload
    public let isSelected: Bool
    public let onClick: () -> Void

    @State private var isHovered: Bool = false

    public var body: some View {
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 6) {
                Text(match.prefix)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : (isHovered ? .accentColor : .primary))
                    .lineLimit(1)

                Text(previewText(match.expansion))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? Color.white.opacity(0.82) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                if isSelected {
                    Text("↵")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 25, maxHeight: 25)
            // Plain buttons only hit-test opaque content; make the whole row (incl. Spacer) clickable
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(rowBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.primary.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private func previewText(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > 30 ? String(clean.prefix(30)) + "…" : clean
    }
}
