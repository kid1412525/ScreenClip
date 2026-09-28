import Carbon
import Cocoa

/// One global hot key combination, stored as the Carbon key code + modifier
/// mask that RegisterEventHotKey wants, and rendered as "⌘⇧4" for display.
struct KeyboardShortcut: Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey / shiftKey / optionKey / controlKey).
    var modifiers: UInt32

    // MARK: - Storage

    /// "keyCode:modifiers" — compact enough to keep in UserDefaults as one
    /// string, and easy to eyeball when debugging a stored value.
    var rawValue: String { "\(keyCode):\(modifiers)" }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":")
        guard parts.count == 2, let keyCode = UInt32(parts[0]), let modifiers = UInt32(parts[1]) else {
            return nil
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - From a key press

    /// nil when the press can't work as a global hot key: a bare key, or one
    /// held with Shift alone, would fire while typing anywhere in macOS.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }

        let needsModifier = !Self.isFunctionKey(UInt32(event.keyCode))
        let hasRealModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard !needsModifier || hasRealModifier else { return nil }

        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
    }

    // MARK: - Display

    var displayString: String {
        Self.modifierSymbols(modifiers) + Self.keyName(for: keyCode)
    }

    /// macOS renders modifiers in this order regardless of press order.
    private static func modifierSymbols(_ modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    // MARK: - Menu item form

    /// NSMenuItem wants a character plus AppKit flags rather than a key code.
    /// nil for keys with no sensible character form — the caller then leaves
    /// the menu item without a key equivalent (the global hot key still works).
    var menuKeyEquivalent: String? {
        if let name = Self.functionKeyNames[keyCode], let number = Int(name.dropFirst()) {
            return Self.functionKeyCharacter(NSF1FunctionKey + number - 1)
        }
        switch Int(keyCode) {
        case kVK_Space: return " "
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Escape: return "\u{1b}"
        case kVK_Delete: return "\u{8}"
        case kVK_ForwardDelete: return Self.functionKeyCharacter(NSDeleteFunctionKey)
        case kVK_Home: return Self.functionKeyCharacter(NSHomeFunctionKey)
        case kVK_End: return Self.functionKeyCharacter(NSEndFunctionKey)
        case kVK_PageUp: return Self.functionKeyCharacter(NSPageUpFunctionKey)
        case kVK_PageDown: return Self.functionKeyCharacter(NSPageDownFunctionKey)
        case kVK_LeftArrow: return Self.functionKeyCharacter(NSLeftArrowFunctionKey)
        case kVK_RightArrow: return Self.functionKeyCharacter(NSRightArrowFunctionKey)
        case kVK_UpArrow: return Self.functionKeyCharacter(NSUpArrowFunctionKey)
        case kVK_DownArrow: return Self.functionKeyCharacter(NSDownArrowFunctionKey)
        default: return Self.printableName(for: keyCode)?.lowercased()
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    private static func functionKeyCharacter(_ value: Int) -> String? {
        UnicodeScalar(UInt32(value)).map { String($0) }
    }

    private static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    private static let functionKeyNames: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = functionKeyNames[keyCode] ?? specialKeyNames[keyCode] { return name }
        return printableName(for: keyCode) ?? "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what this key prints, so a JIS or
    /// AZERTY layout shows the label that's actually on the user's key.
    private static func printableName(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
