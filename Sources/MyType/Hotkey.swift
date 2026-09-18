import AppKit
import CoreGraphics

/// Fn (Globe) and Right Option press/release events via a listen-only CGEventTap. Needs Input Monitoring permission.
final class Hotkey {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    private var tap: CFMachPort?
    private var isDown = false

    func install() -> Bool {
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
