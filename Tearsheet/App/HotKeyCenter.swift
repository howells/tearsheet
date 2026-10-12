import Carbon.HIToolbox

/// Global shortcuts through Carbon hot keys, which need no Accessibility
/// permission. While macOS still claims ⇧⌘4 its own screenshot runs as well,
/// so Tearsheet offers to switch that off and then registers again.
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int

        static let captureRegion = Shortcut(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey)
        static let captureIntoEditor = Shortcut(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | optionKey)
        static let repeatLastRegion = Shortcut(keyCode: kVK_ANSI_6, modifiers: cmdKey | shiftKey)
        static let extractImages = Shortcut(keyCode: kVK_ANSI_I, modifiers: cmdKey | shiftKey | optionKey)
    }

    private var shortcuts: [UInt32: Shortcut] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        let id = UInt32(actions.count + 1)
        shortcuts[id] = shortcut
        actions[id] = action
        install(id)
    }

    /// Registers every shortcut afresh, for when macOS has just let go of one.
    func reinstall() {
        for (id, ref) in hotKeys { UnregisterEventHotKey(ref); hotKeys[id] = nil }
        for id in shortcuts.keys { install(id) }
    }

    private func install(_ id: UInt32) {
        guard let shortcut = shortcuts[id] else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), EventHotKeyID(signature: OSType(0x5452_5348), id: id), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotKeys[id] = ref }
    }
}
