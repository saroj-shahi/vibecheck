import Carbon.HIToolbox
import Foundation

/// Global shortcuts (modifier + 1…7) that open each module's panel from any app.
/// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: ((Module) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    private static let signature: OSType = 0x5649_4245 // "VIBE"
    private static let keyCodes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                   kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]

    func register(modifier: HotkeyModifier) {
        unregisterAll()
        installHandlerIfNeeded()
        let flags: Int
        switch modifier {
        case .controlOptionCommand: flags = controlKey | optionKey | cmdKey
        case .controlOption: flags = controlKey | optionKey
        case .optionCommand: flags = optionKey | cmdKey
        }
        for (index, _) in Module.allCases.enumerated() where index < Self.keyCodes.count {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            let status = RegisterEventHotKey(UInt32(Self.keyCodes[index]), UInt32(flags), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { NSLog("VibeCheck: shortcut \(modifier.symbols)\(Module.allCases[index].shortcutKey ?? "?") unavailable (\(status))") }
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    fileprivate func fire(_ index: Int) {
        guard Module.allCases.indices.contains(index) else { return }
        onTrigger?(Module.allCases[index])
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyManager.signature else { return status }
            let index = Int(id.id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotkeyManager.shared.fire(index) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
