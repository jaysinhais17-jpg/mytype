import AppKit
import CoreGraphics

/// Fn (Globe) and Right Option press/release events via a listen-only CGEventTap. Needs Input Monitoring permission.
final class Hotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onEvent: ((Int64, Bool) -> Void)?
    private var tap: CFMachPort?
    private var isDown = false
    var installed: Bool { tap != nil }

    func install() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let pressed: Bool
            switch code {
            case 63: pressed = event.flags.contains(.maskSecondaryFn)   // Fn / Globe
            case 61: pressed = event.flags.contains(.maskAlternate)     // Right Option
            default: return Unmanaged.passUnretained(event)
            }
            DispatchQueue.main.async { me.onEvent?(code, pressed) }
            if pressed && !me.isDown { me.isDown = true; DispatchQueue.main.async { me.onDown?() } }
            else if !pressed && me.isDown { me.isDown = false; DispatchQueue.main.async { me.onUp?() } }
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
