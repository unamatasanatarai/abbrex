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
        if let rect = focusedCaretRect() {
            return computePosition(for: rect, popupWidth: popupWidth, popupHeight: popupHeight)
        }

        // Chromium and Electron only build their accessibility tree once a client asks for it. The tree is
        // populated asynchronously, so after turning it on give the app a moment and look again.
        if let app = NSWorkspace.shared.frontmostApplication, enableAccessibility(for: app) {
            for _ in 0..<5 {
                usleep(30_000)
                if let rect = focusedCaretRect() {
                    return computePosition(for: rect, popupWidth: popupWidth, popupHeight: popupHeight)
                }
            }
        }

        // Final Fallback: no accessible focused element, anchor popup near current mouse cursor location
        let mouseLocation = NSEvent.mouseLocation
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080
        // Convert screen flipped coordinates
        let cgMousePoint = CGPoint(x: mouseLocation.x, y: primaryScreenHeight - mouseLocation.y)
        return computePosition(for: CGRect(origin: cgMousePoint, size: CGSize(width: 1, height: 20)), popupWidth: popupWidth, popupHeight: popupHeight)
    }

    /// PIDs for which switching on the accessibility tree has been attempted, so it is attempted once per process.
    private static var accessibilityAttemptedPIDs = Set<pid_t>()
    /// PIDs whose accessibility tree was switched on by us. Their AX text writes report success without
    /// changing the visible text, so TextReplacer must type into them instead.
    private static var accessibilityEnabledPIDs = Set<pid_t>()

    public static func didEnableAccessibility(for pid: pid_t) -> Bool {
        // The tree may already be on from a previous AbbrEx run; switching it on again is harmless and tells us
        if !accessibilityAttemptedPIDs.contains(pid), let app = NSRunningApplication(processIdentifier: pid) {
            enableAccessibility(for: app)
        }
        return accessibilityEnabledPIDs.contains(pid)
    }

    /// Asks Electron (`AXManualAccessibility`) or Chromium (`AXEnhancedUserInterface`) apps to expose their
    /// accessibility tree, which they otherwise keep off unless VoiceOver is running.
    /// - Returns: `true` if the tree was switched on by this call.
    @discardableResult
    public static func enableAccessibility(for app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier,
              !accessibilityAttemptedPIDs.contains(pid) else { return false }
        accessibilityAttemptedPIDs.insert(pid)

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        var enabled = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue) == .success
        // AXEnhancedUserInterface interferes with window animations, so only use it where the app needs it
        if !enabled && isChromiumBased(app) {
            enabled = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) == .success
        }
        if enabled {
            accessibilityEnabledPIDs.insert(pid)
        }
        return enabled
    }

    private static func isChromiumBased(_ app: NSRunningApplication) -> Bool {
        guard let bundleURL = app.bundleURL else { return false }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { $0.hasSuffix("Framework.framework") && ($0.contains("Chrome") || $0.contains("Chromium") || $0.contains("Electron") || $0.contains("Edge") || $0.contains("Brave")) }
    }

    private static func focusedCaretRect() -> CGRect? {
        guard let element = focusedElement() else { return nil }
        // 1. Google Docs caret element (typing goes to an offscreen proxy field)
        // 2. Text range bounds (native Cocoa text views and most apps)
        // 3. Text marker bounds (Safari, Chrome, Electron and other web content)
        // 4. Element frame (caret position not exposed at all)
        return caretRectFromGoogleDocs(element)
            ?? caretRectFromTextRange(element)
            ?? caretRectFromTextMarkers(element)
            ?? elementFrameAnchor(element)
    }

    /// Google Docs renders text on a canvas and routes keystrokes into a 1pt-tall `docs-texteventtarget-iframe`
    /// parked offscreen, so its text bounds are meaningless. The visible caret is a `kix-cursor-caret` element.
    private static func caretRectFromGoogleDocs(_ axElement: AXUIElement) -> CGRect? {
        var current = axElement
        var proxyFrame: AXUIElement?
        for _ in 0..<4 {
            guard let parent = copyElement(current, kAXParentAttribute) else { return nil }
            if domClasses(parent).contains("docs-texteventtarget-iframe") {
                proxyFrame = parent
                break
            }
            current = parent
        }
        guard let proxy = proxyFrame, let editor = copyElement(proxy, kAXParentAttribute) else { return nil }

        // Breadth-first: the caret sits ~15 levels below the editor container in a few hundred nodes
        var queue: [AXUIElement] = [editor]
        var carets: [(rect: CGRect, isBlinking: Bool)] = []
        var visited = 0
        while !queue.isEmpty && visited < 3000 {
            let node = queue.removeFirst()
            visited += 1
            if CFEqual(node, proxy) { continue }

            let classes = domClasses(node)
            if classes.contains("kix-cursor"), let caret = elementFrame(node), isPlausibleCaret(caret) {
                // Collaborators' cursors share the class; only the local one blinks
                carets.append((caret, classes.contains("docs-text-ui-cursor-blink")))
                continue
            }
            queue.append(contentsOf: copyChildren(node))
        }

        guard let caret = carets.first(where: { $0.isBlinking })?.rect ?? (carets.count == 1 ? carets[0].rect : nil) else {
            return nil
        }
        return CGRect(x: caret.minX, y: caret.minY, width: 2, height: caret.height)
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let ref = value, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func domClasses(_ element: AXUIElement) -> [String] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value) == .success else { return [] }
        return (value as? [String]) ?? []
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var positionVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionVal) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let pos = positionVal, let sz = sizeVal else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &point),
              AXValueGetValue(sz as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
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
        if AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect), isPlausibleCaret(rect), rect.width <= 4 {
            return CGRect(x: rect.minX, y: rect.origin.y, width: 2, height: rect.height)
        }

        // A collapsed caret should be (nearly) zero-width. Chromium/Electron return the whole field's bounds instead
        // (e.g. 579x40 in Antigravity), so measure the character next to the caret and anchor to its edge.
        guard CFGetTypeID(markers) == AXTextMarkerRangeGetTypeID() else { return nil }
        let caretMarker = AXTextMarkerRangeCopyEndMarker(markers as! AXTextMarkerRange)

        if let prev = adjacentMarker(axElement, "AXPreviousTextMarkerForTextMarker", caretMarker),
           let charRect = boundsForMarkers(axElement, from: prev, to: caretMarker) {
            return CGRect(x: charRect.maxX, y: charRect.origin.y, width: 2, height: charRect.height)
        }
        if let next = adjacentMarker(axElement, "AXNextTextMarkerForTextMarker", caretMarker),
           let charRect = boundsForMarkers(axElement, from: caretMarker, to: next) {
            return CGRect(x: charRect.minX, y: charRect.origin.y, width: 2, height: charRect.height)
        }
        return nil
    }

    private static func adjacentMarker(_ axElement: AXUIElement, _ attribute: String, _ marker: AXTextMarker) -> AXTextMarker? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(axElement, attribute as CFString, marker, &result) == .success,
              let value = result, CFGetTypeID(value) == AXTextMarkerGetTypeID() else { return nil }
        return (value as! AXTextMarker)
    }

    /// Bounds of a single-character marker range, rejecting the whole-field rects some apps return.
    private static func boundsForMarkers(_ axElement: AXUIElement, from start: AXTextMarker, to end: AXTextMarker) -> CGRect? {
        let range = AXTextMarkerRangeCreate(kCFAllocatorDefault, start, end)
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(axElement, "AXBoundsForTextMarkerRange" as CFString, range, &boundsValue) == .success,
              let boundsVal = boundsValue else { return nil }

        var rect = CGRect.zero
        // A newline yields a zero-width rect at line end, which is still a valid caret anchor
        guard AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect), isPlausibleCaret(rect), rect.width < 80 else { return nil }
        return rect
    }

    private static func elementFrameAnchor(_ axElement: AXUIElement) -> CGRect? {
        // A few-points-tall element is a hidden input proxy, not a visible control worth anchoring to
        guard let frame = elementFrame(axElement), frame.height >= 4, isOnAnyScreen(frame.origin) else { return nil }

        // Anchor caret near current input control content area
        return CGRect(x: frame.minX + 8, y: frame.minY + 4, width: 2, height: min(frame.height, 22))
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
