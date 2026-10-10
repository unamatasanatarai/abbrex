import AppKit
import SwiftUI

/// Floating borderless NSPanel for text caret anchored overlay UI.
public final class OverlayPanel: NSPanel {

    public var onCandidateSelected: ((Int) -> Void)?
    private let candidateViewModel = CandidateViewModel()

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: AppConfig.popupWidth, height: AppConfig.popupMaxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Initialize SwiftUI hosting view ONCE for lifetime of the panel
        let candidateView = CandidateListView(
            viewModel: candidateViewModel,
            onSelectCandidate: { [weak self] index in
                self?.onCandidateSelected?(index)
            }
        )
        self.contentView = NSHostingView(rootView: candidateView)
    }

    /// Shows overlay popup positioned relative to screen caret coordinates.
    public func show(matches: [ExpansionPayload], selectedIndex: Int, caretRect: CaretTracker.CaretRect) {
        // Zero-allocation reactive update to existing view graph
        candidateViewModel.matches = matches
        candidateViewModel.selectedIndex = selectedIndex

        // Calculate dynamic height based on candidate match count (compact 26px rows + 6px padding)
        let contentHeight = min(CGFloat(matches.count) * 26 + 6, AppConfig.popupMaxHeight)
        let contentWidth = AppConfig.popupWidth

        // Compute anchored window origin relative to caret corner
        let targetOrigin = CaretTracker.calculateAnchoredOrigin(
            for: caretRect,
            panelWidth: contentWidth,
            panelHeight: contentHeight
        )

        let newFrame = NSRect(origin: targetOrigin, size: NSSize(width: contentWidth, height: contentHeight))
        if self.frame != newFrame {
            self.setFrame(newFrame, display: true, animate: false)
        }
        if !self.isVisible {
            self.orderFront(nil)
        }
    }

    /// Hides overlay popup.
    public func dismiss() {
        guard self.isVisible else { return }
        self.orderOut(nil)
    }
}
