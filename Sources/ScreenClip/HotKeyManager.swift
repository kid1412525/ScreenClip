import Carbon
import Cocoa

/// Registers a single global hot key via the Carbon Event Manager.
/// This does not require Accessibility/Input Monitoring permission,
/// unlike NSEvent global monitors.
final class HotKeyManager {
    typealias Handler = () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: Handler
    private let hotKeyID: EventHotKeyID

    /// Each instance needs a distinct id — InstallEventHandler is called per
    /// instance but they all share the same application-wide event target,
    /// so every installed handler's callback fires for every hotkey press;
    /// a shared id would make every handler think each press was its own.
    private static var nextID: UInt32 = 1

    init(shortcut: KeyboardShortcut, handler: @escaping Handler) {
        self.hotKeyID = EventHotKeyID(signature: OSType(0x53434C50), id: Self.nextID) // 'SCLP'
        Self.nextID += 1
        self.handler = handler
        installEventHandler()
        register(shortcut)
    }

    /// Swaps in a new combination. Returns false and keeps nothing registered
    /// when the system or another app already owns the combination — the
    /// caller decides what to tell the user.
    @discardableResult
    func register(_ shortcut: KeyboardShortcut) -> Bool {
        unregister()
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
            return false
        }
        return true
    }

    /// Releases the combination without tearing down the event handler, so
    /// the key press reaches the app normally (used while recording a new
    /// shortcut in 環境設定).
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, eventRef, userData) -> OSStatus in
                guard let eventRef else { return noErr }
                var receivedID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                if let userData {
                    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    if receivedID.id == manager.hotKeyID.id {
                        manager.handler()
                    }
                }
                // Multiple HotKeyManager instances share GetApplicationEventTarget(),
                // each installing its own handler. Without forwarding to the next
                // one in the chain, whichever handler runs first (the most
                // recently installed) swallows every event for every hotkey,
                // since returning noErr here marks the event as fully handled.
                return CallNextEventHandler(nextHandler, eventRef)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
