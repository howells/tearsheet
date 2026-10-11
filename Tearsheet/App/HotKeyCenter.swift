import Carbon.HIToolbox

/// Global shortcuts through Carbon hot keys, which need no Accessibility
/// permission. A shortcut macOS still owns (⇧⌘4 before it is switched off in
/// System Settings) registers fine but never reaches us.
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: Int
        let modifiers: Int

        static let captureRegion = Shortcut(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey)
        static let captureIntoEditor = Shortcut(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey | optionKey)
        static let repeatLastRegion = Shortcut(keyCode: kVK_ANSI_6, modifiers: cmdKey | shiftKey)
    }

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeys: [EventHotKeyRef] = []
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
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), EventHotKeyID(signature: OSType(0x5452_5348), id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        hotKeys.append(ref)
        actions[id] = action
    }
}
