import AppKit
import CoreGraphics

/// Fn (Globe) and Right Option press/release events via a listen-only CGEventTap. Needs Input Monitoring permission.
final class Hotkey {
    /// The Date is when the key actually moved. Handlers run later on the main queue, which can be busy for a few
    /// hundred ms starting the mic, so timing a tap from inside them misreads quick taps as holds.
    var onDown: ((Int64, Date) -> Void)?
    /// Second argument: another key was pressed while this one was held (a shortcut like Option+E, not a dictation press).
    var onUp: ((Int64, Bool, Date) -> Void)?
    var onEvent: ((Int64, Bool) -> Void)?
    private var tap: CFMachPort?
    private var down: Set<Int64> = []
    private var chorded = false
    var installed: Bool { tap != nil }

    func install() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                if !me.down.isEmpty { me.chorded = true }
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let pressed: Bool
            switch code {
            case 63: pressed = event.flags.contains(.maskSecondaryFn)   // Fn / Globe
            case 61: pressed = event.flags.contains(.maskAlternate)     // Right Option
            default: return Unmanaged.passUnretained(event)
            }
            let at = Date()
            DispatchQueue.main.async { me.onEvent?(code, pressed) }
            if pressed && !me.down.contains(code) {
                if me.down.isEmpty { me.chorded = false }
                me.down.insert(code)
                DispatchQueue.main.async { me.onDown?(code, at) }
            } else if !pressed && me.down.contains(code) {
                me.down.remove(code)
                let c = me.chorded
                DispatchQueue.main.async { me.onUp?(code, c, at) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .listenOnly, eventsOfInterest: mask,
                                        callback: cb, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }
}
