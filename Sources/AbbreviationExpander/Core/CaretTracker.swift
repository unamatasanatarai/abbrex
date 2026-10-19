import Foundation
import AppKit
import ApplicationServices

/// Caret position tracker using macOS Accessibility APIs (AXUIElement).
public final class CaretTracker {

    private static let systemWide = AXUIElementCreateSystemWide()

    public struct CaretRect {
        public let origin: CGPoint
        public let height: CGFloat
        public let isFlippedAbove: Bool
        public let isFlippedLeft: Bool
        public let screenFrame: CGRect
        public let visibleFrame: CGRect
        /// Height of the primary screen, the reference for converting AX top-left Y to AppKit bottom-left Y.
        public let primaryScreenHeight: CGFloat

        public init(
            origin: CGPoint,
            height: CGFloat,
            isFlippedAbove: Bool,
            isFlippedLeft: Bool,
            screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
            primaryScreenHeight: CGFloat? = nil
        ) {
            self.origin = origin
            self.height = height
            self.isFlippedAbove = isFlippedAbove
            self.isFlippedLeft = isFlippedLeft
            self.screenFrame = screenFrame
            self.visibleFrame = visibleFrame
            self.primaryScreenHeight = primaryScreenHeight ?? screenFrame.maxY
        }
    }

    /// Fetches the screen coordinates for the current active text caret across macOS applications.
    /// - Parameters:
    ///   - popupWidth: Width of the overlay popup to perform boundary detection.
    ///   - popupHeight: Height of the overlay popup to perform boundary detection.
    /// - Returns: Calculated CaretRect with target top-left point and flip flags.
    public static func getCaretScreenPosition(popupWidth: CGFloat = 240, popupHeight: CGFloat = 150) -> CaretRect {
        if let element = focusedElement() {
            // 1. Text range bounds (native Cocoa text views and most apps)
            // 2. Text marker bounds (Safari, Chrome, Electron and other web content)
            // 3. Element frame (caret position not exposed at all)
            if let rect = caretRectFromTextRange(element) ?? caretRectFromTextMarkers(element) ?? elementFrameAnchor(element) {
                return computePosition(for: rect, popupWidth: popupWidth, popupHeight: popupHeight)
            }
        }

        // Final Fallback: no accessible focused element, anchor popup near current mouse cursor location
        let mouseLocation = NSEvent.mouseLocation
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        // Convert screen flipped coordinates
        let cgMousePoint = CGPoint(x: mouseLocation.x, y: primaryScreenHeight - mouseLocation.y)
        return computePosition(for: CGRect(origin: cgMousePoint, size: CGSize(width: 1, height: 20)), popupWidth: popupWidth, popupHeight: popupHeight)
    }

    /// Resolves the focused UI element, preferring the frontmost application over the system-wide element.
    private static func focusedElement() -> AXUIElement? {
        var focused: CFTypeRef?

        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
               let element = focused {
                return (element as! AXUIElement)
            }
        }

        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let element = focused {
            return (element as! AXUIElement)
        }
        return nil
    }

    private static func caretRectFromTextRange(_ axElement: AXUIElement) -> CGRect? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
              let rangeVal = selectedRangeValue else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeVal as! AXValue, .cfRange, &range) else { return nil }

        // Zero-length caret range bounds
        let caretRange = CFRange(location: range.location + range.length, length: 0)
        if let rect = fetchBoundsForRange(axElement: axElement, range: caretRange), isPlausibleCaret(rect) {
            return CGRect(x: rect.origin.x, y: rect.origin.y, width: 2, height: rect.height)
        }

        // Previous character range bounds (for web/electron apps where zero-length range bounds return empty)
        let caretLocation = range.location + range.length
        if caretLocation > 0 {
            let prevCharRange = CFRange(location: caretLocation - 1, length: 1)
            if let charRect = fetchBoundsForRange(axElement: axElement, range: prevCharRange), isPlausibleCaret(charRect) {
                // Caret is positioned immediately at the right edge of the typed character
                return CGRect(x: charRect.maxX, y: charRect.origin.y, width: 2, height: charRect.height)
            }
        } else {
            let firstCharRange = CFRange(location: 0, length: 1)
            if let charRect = fetchBoundsForRange(axElement: axElement, range: firstCharRange), isPlausibleCaret(charRect) {
                return CGRect(x: charRect.origin.x, y: charRect.origin.y, width: 2, height: charRect.height)
            }
        }
        return nil
    }

    private static func caretRectFromTextMarkers(_ axElement: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let markers = markerRange else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(axElement, "AXBoundsForTextMarkerRange" as CFString, markers, &boundsValue) == .success,
              let boundsVal = boundsValue else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect), isPlausibleCaret(rect) else { return nil }
        // A selection spans the whole range; anchor to its trailing edge where the caret sits
        return CGRect(x: rect.maxX, y: rect.origin.y, width: 2, height: rect.height)
    }

    private static func elementFrameAnchor(_ axElement: AXUIElement) -> CGRect? {
        var positionVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionVal) == .success,
              AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let pos = positionVal, let sz = sizeVal else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &point)
        AXValueGetValue(sz as! AXValue, .cgSize, &size)
        guard size.height > 0, isOnAnyScreen(point) else { return nil }

        // Anchor caret near current input control content area
        return CGRect(x: point.x + 8, y: point.y + 4, width: 2, height: min(size.height, 22))
    }

    /// Rejects the zero/garbage rects some apps return instead of failing (a caret may legitimately be 0pt wide).
    private static func isPlausibleCaret(_ rect: CGRect) -> Bool {
        guard rect.height > 0, rect.height < 200, rect.origin != .zero else { return false }
        return isOnAnyScreen(rect.origin)
    }

    /// Checks a point in AX (top-left, primary-screen-relative) coordinates against all screens.
    private static func isOnAnyScreen(_ point: CGPoint) -> Bool {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        return NSScreen.screens.contains { screen in
            CGRect(
                x: screen.frame.origin.x,
                y: primaryScreenHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            ).insetBy(dx: -1, dy: -1).contains(point)
        }
    }

    private static func fetchBoundsForRange(axElement: AXUIElement, range: CFRange) -> CGRect? {
        var mutableRange = range
        guard let rangeVal = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal,
            &boundsValue
        )

        if boundsResult == .success, let boundsVal = boundsValue {
            var rect = CGRect.zero
            if AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect) {
                return rect
            }
        }
        return nil
    }

    private static func computePosition(for caretRect: CGRect, popupWidth: CGFloat = 240, popupHeight: CGFloat = 150) -> CaretRect {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        let targetScreen = NSScreen.screens.first(where: { screen in
            let axTopLeftScreenFrame = CGRect(
                x: screen.frame.origin.x,
                y: mainScreenHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height
            )
            return axTopLeftScreenFrame.contains(caretRect.origin)
        }) ?? NSScreen.main

        guard let screen = targetScreen else {
            return CaretRect(origin: caretRect.origin, height: caretRect.height, isFlippedAbove: false, isFlippedLeft: false, primaryScreenHeight: mainScreenHeight)
        }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame

        // Convert AX Top-Left y coordinate (relative to primary screen) to AppKit Bottom-Left y coordinate
        let caretTopInAppKit = mainScreenHeight - caretRect.origin.y
        let caretBottomInAppKit = caretTopInAppKit - caretRect.height

        // 1. VERTICAL (Y-Axis): Default to BELOW caret
        var targetY = caretBottomInAppKit - popupHeight - 4
        var isFlippedAbove = false

        // If placing below overflows screen bottom (Dock / visibleFrame minX), flip to ABOVE caret
        if targetY < visibleFrame.minY + 10 {
            targetY = caretTopInAppKit + 4
            isFlippedAbove = true

            // If placing above overflows screen top (Menu Bar / visibleFrame maxY), clamp inside visible area
            if targetY + popupHeight > visibleFrame.maxY - 10 {
                targetY = max(visibleFrame.minY + 10, min(caretBottomInAppKit - popupHeight - 4, visibleFrame.maxY - popupHeight - 10))
                isFlippedAbove = false
            }
        }

        // 2. HORIZONTAL (X-Axis): Default to LEFT-ALIGNED with caret
        var targetX = caretRect.origin.x
        var isFlippedLeft = false

        // If placing to the right overflows screen right boundary, flip to OPPOSITE side (LEFT of caret)
        if targetX + popupWidth > visibleFrame.maxX - 10 {
            targetX = caretRect.origin.x - popupWidth
            isFlippedLeft = true
            // If flipping left also overflows screen left boundary, clamp inside visible frame
            if targetX < visibleFrame.minX + 10 {
                targetX = visibleFrame.maxX - popupWidth - 10
                isFlippedLeft = false
            }
        }

        // If placing to the left overflows screen left boundary, clamp inside visible frame
        if targetX < visibleFrame.minX + 10 {
            targetX = visibleFrame.minX + 10
        }

        return CaretRect(
            origin: caretRect.origin,
            height: caretRect.height,
            isFlippedAbove: isFlippedAbove,
            isFlippedLeft: isFlippedLeft,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            primaryScreenHeight: mainScreenHeight
        )
    }

    /// Calculates exact AppKit Bottom-Left origin for dynamic popout dimensions, anchoring to the cursor corner.
    public static func calculateAnchoredOrigin(for caretRect: CaretRect, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        let visibleFrame = caretRect.visibleFrame

        // Convert AX Top-Left y coordinate (relative to primary screen) to AppKit Bottom-Left y coordinate
        let caretTopInAppKit = caretRect.primaryScreenHeight - caretRect.origin.y
        let caretBottomInAppKit = caretTopInAppKit - caretRect.height

        // 1. VERTICAL ANCHORING
        var originY: CGFloat
        if caretRect.isFlippedAbove {
            // Popup is ABOVE caret: Bottom edge of popup is fixed at caretTopInAppKit + 4
            originY = caretTopInAppKit + 4
        } else {
            // Popup is BELOW caret: Top edge of popup is fixed at caretBottomInAppKit - 4
            // Therefore, bottom-left origin Y is (caretBottomInAppKit - 4) - panelHeight
            originY = (caretBottomInAppKit - 4) - panelHeight
        }

        // Clamp Y inside visible screen bounds
        originY = max(visibleFrame.minY + 4, min(originY, visibleFrame.maxY - panelHeight - 4))

        // 2. HORIZONTAL ANCHORING
        var originX: CGFloat
        if caretRect.isFlippedLeft {
            // Popup is to the LEFT of caret: Right edge of popup is fixed at caretRect.origin.x
            originX = caretRect.origin.x - panelWidth
        } else {
            // Popup is to the RIGHT of caret: Left edge of popup is fixed at caretRect.origin.x
            originX = caretRect.origin.x
        }

        // Clamp X inside visible screen bounds
        originX = max(visibleFrame.minX + 4, min(originX, visibleFrame.maxX - panelWidth - 4))

        return CGPoint(x: originX, y: originY)
    }
}
