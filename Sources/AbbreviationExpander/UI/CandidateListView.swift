import SwiftUI
import AppKit

/// Floating accessible overlay list view displaying candidate abbreviation matches.
public struct CandidateListView: View {
    public let matches: [ExpansionPayload]
    public let selectedIndex: Int
    public var onSelectCandidate: ((Int) -> Void)?

    public init(matches: [ExpansionPayload], selectedIndex: Int, onSelectCandidate: ((Int) -> Void)? = nil) {
        self.matches = matches
        self.selectedIndex = selectedIndex
        self.onSelectCandidate = onSelectCandidate
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Main Glassmorphism Popout Card containing candidates (Prefix monitoring removed!)
            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                                CandidateRow(
                                    match: match,
                                    isSelected: index == selectedIndex
                                ) {
                                    onSelectCandidate?(index)
                                }
                                .id(match.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: selectedIndex) { newIndex in
                        if newIndex >= 0 && newIndex < matches.count {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(matches[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(width: AppConfig.popupWidth, height: min(CGFloat(matches.count * 46 + 14), AppConfig.popupMaxHeight))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            // Transparent Instruction Badge outside the popout box (bottom-right aligned)
            HStack {
                Spacer()
                Text("Tab / Enter / ⌃L / ↵ Click")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.65))
                    .padding(.horizontal, 4)
            }
            .frame(width: AppConfig.popupWidth)
        }
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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.prefix)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : (isHovered ? .accentColor : .primary))

                    Text(previewText(match.expansion))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if isHovered {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.primary.opacity(0.12)
        } else {
            return Color.clear
        }
    }

    private func previewText(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ↵ ")
        return clean.count > 42 ? String(clean.prefix(42)) + "…" : clean
    }
}
