import AppKit
import ApplicationServices
import CoreGraphics

enum Paster {
    /// Cmd+Z in the frontmost app: takes back the last paste.
    static func undo() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 6, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 6, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }

    /// Put text on the clipboard, send Cmd+V to the frontmost app, then restore the old clipboard.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Posting keystrokes without Accessibility trust makes macOS show the "control this Mac" dialog every time.
        // Without trust, leave the text on the clipboard (Cmd+V it yourself) and don't restore the old contents.
        guard AXIsProcessTrusted() else { return }

        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            pb.clearContents()
            for item in saved {
                let n = NSPasteboardItem()
                for (t, d) in item { n.setData(d, forType: t) }
                pb.writeObjects([n])
            }
        }
    }
}
