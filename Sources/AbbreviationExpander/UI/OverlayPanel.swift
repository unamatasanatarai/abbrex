import AppKit
import SwiftUI

/// Floating borderless NSPanel for text caret anchored overlay UI.
public final class OverlayPanel: NSPanel {

    public var onCandidateSelected: ((Int) -> Void)?

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
    }

    /// Shows overlay popup positioned relative to screen caret coordinates.
    public func show(matches: [ExpansionPayload], selectedIndex: Int, buffer: String, caretRect: CaretTracker.CaretRect) {
        let candidateView = CandidateListView(
            matches: matches,
            selectedIndex: selectedIndex,
            buffer: buffer,
            onSelectCandidate: { [weak self] index in
                self?.onCandidateSelected?(index)
            }
        )
        self.contentView = NSHostingView(rootView: candidateView)

        // Calculate dynamic height based on candidate match count
        let contentHeight = min(CGFloat(matches.count * 46 + 28), AppConfig.popupMaxHeight)
        let contentWidth = AppConfig.popupWidth

        // Compute anchored window origin relative to caret corner
        let targetOrigin = CaretTracker.calculateAnchoredOrigin(
            for: caretRect,
            panelWidth: contentWidth,
            panelHeight: contentHeight
        )

        let newFrame = NSRect(origin: targetOrigin, size: NSSize(width: contentWidth, height: contentHeight))
        self.setFrame(newFrame, display: true, animate: false)
        self.orderFront(nil)
    }

    /// Hides overlay popup.
    public func dismiss() {
        self.orderOut(nil)
    }
}
