import Carbon
import Cocoa

extension Notification.Name {
    /// Posted while a shortcut is being recorded, so AppDelegate can release
    /// its global hot keys — Carbon consumes those before the app ever sees
    /// the key press, which would otherwise make the current shortcut
    /// impossible to re-record (it would just fire a capture instead).
    static let shortcutRecordingBegan = Notification.Name("ScreenClip.shortcutRecordingBegan")
    static let shortcutRecordingEnded = Notification.Name("ScreenClip.shortcutRecordingEnded")
}

/// A button that displays a shortcut and, when clicked, waits for the next
/// key press and reports it.
final class ShortcutRecorderButton: NSButton {
    /// Return false to reject the combination (e.g. it's already taken);
    /// the button then keeps showing the previous shortcut.
    var onShortcutRecorded: ((KeyboardShortcut) -> Bool)?

    var shortcut: KeyboardShortcut? {
        didSet { updateTitle() }
    }

    private var monitor: Any?
    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            updateTitle()
            NotificationCenter.default.post(
                name: isRecording ? .shortcutRecordingBegan : .shortcutRecordingEnded,
                object: nil
            )
        }
    }

    init(shortcut: KeyboardShortcut?) {
        self.shortcut = shortcut
        super.init(frame: .zero)

        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func updateTitle() {
        if isRecording {
            title = "キーを押してください..."
        } else {
            title = shortcut?.displayString ?? "未設定"
        }
    }

    @objc private func startRecording() {
        guard !isRecording else {
            stopRecording()
            return
        }
        isRecording = true

        // A local monitor sees the press before the menu bar's key
        // equivalents do, so combinations like ⌘S can still be recorded.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard event.type == .keyDown else { return nil }

            if event.keyCode == UInt16(kVK_Escape), event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.stopRecording()
                return nil
            }
            if let recorded = KeyboardShortcut(event: event) {
                if self.onShortcutRecorded?(recorded) ?? false {
                    self.shortcut = recorded
                }
                self.stopRecording()
            }
            // Swallow everything while recording, including combinations that
            // were rejected — otherwise a rejected ⌘Q would quit the app.
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }

    /// Clicking elsewhere should cancel rather than leave the button armed.
    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
}