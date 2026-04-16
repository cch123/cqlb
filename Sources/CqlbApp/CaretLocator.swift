import AppKit
import ApplicationServices

/// Best-effort "where's the text caret right now?" via the Accessibility API.
///
/// Workflow:
/// 1. Ask the system-wide AX root for the focused UI element.
/// 2. From the focused element, read `AXSelectedTextRange` and map it through
///    `AXBoundsForRange` to get a screen rect.
/// 3. If any step fails (many apps — notably Electron apps, Terminal.app, and
///    Safari's omnibox — don't expose this properly), fall back to the mouse
///    cursor location as an "at least visible" placement.
enum CaretLocator {

    static func currentCaretRect() -> NSRect {
        if let rect = caretRectViaAccessibility() {
            return rect
        }
        // Fallback: mouse cursor.
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x, y: mouse.y, width: 0, height: 0)
    }

    private static func caretRectViaAccessibility() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        var err = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard err == .success, let element = focused else { return nil }
        let focusedElement = element as! AXUIElement

        var rangeValue: AnyObject?
        err = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard err == .success, let range = rangeValue else { return nil }

        var boundsValue: AnyObject?
        err = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsValue
        )
        guard err == .success, let rawBounds = boundsValue else { return nil }

        var rect = CGRect.zero
        if AXValueGetValue(rawBounds as! AXValue, .cgRect, &rect) {
            // AX rects are in a top-left coordinate space; Cocoa screen
            // coordinates are bottom-left. Flip against the main display.
            if let screen = NSScreen.screens.first {
                let flipped = NSRect(
                    x: rect.origin.x,
                    y: screen.frame.maxY - rect.origin.y - rect.height,
                    width: rect.width,
                    height: rect.height
                )
                return flipped
            }
            return rect
        }
        return nil
    }
}
