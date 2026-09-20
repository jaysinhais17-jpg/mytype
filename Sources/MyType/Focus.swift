import AppKit
import ApplicationServices

/// Whether the front app has a text box focused, so a dictation is typed only where you meant it to go.
enum Focus {
    enum Kind {
        case textBox   // a text field or editor has the cursor
        case noBox     // something else is focused (a button, the desktop, a video)
        case unknown   // the app won't say (or Accessibility is off): behave as before and paste
    }

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Browsers and Electron apps often report the whole page for a focused editor, so these prove nothing.
    private static let vagueRoles: Set<String> = ["AXWebArea", "AXGroup", "AXUnknown", ""]

    static func current() -> Kind {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appEl, 0.25)
        var ref: CFTypeRef?
        switch AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &ref) {
        case .success: break
        case .noValue: return .noBox
        default: return .unknown
        }
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return .unknown }
        let el = ref as! AXUIElement
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        let r = role as? String ?? ""
        if textRoles.contains(r) { return .textBox }
        var editable: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editable) == .success, (editable as? Bool) == true { return .textBox }
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success { return .textBox }
        return vagueRoles.contains(r) ? .unknown : .noBox
    }

    /// Chrome and Electron apps only build their accessibility tree once something asks for it.
    static func prime(_ app: NSRunningApplication?) {
        guard let app, AXIsProcessTrusted() else { return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.25)
        AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
