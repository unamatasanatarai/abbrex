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

        public init(
            origin: CGPoint,
            height: CGFloat,
            isFlippedAbove: Bool,
            isFlippedLeft: Bool,
            screenFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        ) {
            self.origin = origin
            self.height = height
            self.isFlippedAbove = isFlippedAbove
            self.isFlippedLeft = isFlippedLeft
            self.screenFrame = screenFrame
            self.visibleFrame = visibleFrame
        }
    }

    /// Fetches the screen coordinates for the current active text caret across macOS applications.
    /// - Parameters:
    ///   - popupWidth: Width of the overlay popup to perform boundary detection.
    ///   - popupHeight: Height of the overlay popup to perform boundary detection.
    /// - Returns: Calculated CaretRect with target top-left point and flip flags.
    public static func getCaretScreenPosition(popupWidth: CGFloat = 340, popupHeight: CGFloat = 220) -> CaretRect {
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement

            var selectedRangeValue: CFTypeRef?
            let rangeResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)

            if rangeResult == .success, let rangeVal = selectedRangeValue {
                var range = CFRange()
                AXValueGetValue(rangeVal as! AXValue, .cfRange, &range)

                // 1. Try zero-length caret range bounds
                if let rect = fetchBoundsForRange(axElement: axElement, range: range), !rect.isEmpty {
                    return computePosition(for: rect, popupWidth: popupWidth, popupHeight: popupHeight)
                }

                // 2. Try previous character range bounds (for web/electron apps where zero-length range bounds return empty)
                if range.location > 0 {
                    let prevCharRange = CFRange(location: range.location - 1, length: 1)
                    if let charRect = fetchBoundsForRange(axElement: axElement, range: prevCharRange), !charRect.isEmpty {
                        // Caret is positioned immediately at the right edge of the typed character
                        let caretRect = CGRect(
                            x: charRect.origin.x + charRect.width,
                            y: charRect.origin.y,
                            width: 2,
                            height: charRect.height
                        )
                        return computePosition(for: caretRect, popupWidth: popupWidth, popupHeight: popupHeight)
                    }
                } else {
                    let firstCharRange = CFRange(location: 0, length: 1)
                    if let charRect = fetchBoundsForRange(axElement: axElement, range: firstCharRange), !charRect.isEmpty {
                        let caretRect = CGRect(
                            x: charRect.origin.x,
                            y: charRect.origin.y,
                            width: 2,
                            height: charRect.height
                        )
                        return computePosition(for: caretRect, popupWidth: popupWidth, popupHeight: popupHeight)
                    }
                }
            }

            // 3. Fallback: Get element frame position and estimate caret line offset
            var positionVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(axElement, kAXPositionAttribute as CFString, &positionVal)
            _ = AXUIElementCopyAttributeValue(axElement, kAXSizeAttribute as CFString, &sizeVal)

            if let pos = positionVal, let sz = sizeVal {
                var point = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(pos as! AXValue, .cgPoint, &point)
                AXValueGetValue(sz as! AXValue, .cgSize, &size)

                // Anchor caret near current input control content area
                let caretRect = CGRect(x: point.x + 8, y: point.y + 4, width: 2, height: min(size.height, 22))
                return computePosition(for: caretRect, popupWidth: popupWidth, popupHeight: popupHeight)
            }
        }

        // Final Fallback: Anchor popup near current mouse cursor location
        let mouseLocation = NSEvent.mouseLocation
        let mainScreenHeight = NSScreen.main?.frame.height ?? 1080
        // Convert screen flipped coordinates
        let cgMousePoint = CGPoint(x: mouseLocation.x, y: mainScreenHeight - mouseLocation.y)
        return computePosition(for: CGRect(origin: cgMousePoint, size: CGSize(width: 1, height: 20)), popupWidth: popupWidth, popupHeight: popupHeight)
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

    private static func computePosition(for caretRect: CGRect, popupWidth: CGFloat = 340, popupHeight: CGFloat = 220) -> CaretRect {
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
            return CaretRect(origin: caretRect.origin, height: caretRect.height, isFlippedAbove: false, isFlippedLeft: false)
        }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame

        // Convert AX Top-Left y coordinate to AppKit Bottom-Left y coordinate
        let caretTopInAppKit = screenFrame.origin.y + (screenFrame.height - caretRect.origin.y)
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
            visibleFrame: visibleFrame
        )
    }

    /// Calculates exact AppKit Bottom-Left origin for dynamic popout dimensions, anchoring to the cursor corner.
    public static func calculateAnchoredOrigin(for caretRect: CaretRect, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint {
        let screenFrame = caretRect.screenFrame
        let visibleFrame = caretRect.visibleFrame

        // Convert AX Top-Left y coordinate to AppKit Bottom-Left y coordinate
        let caretTopInAppKit = screenFrame.origin.y + (screenFrame.height - caretRect.origin.y)
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
