import AppKit
import Carbon.HIToolbox

enum ShortcutAction {
    case togglePlay, faster, slower
    case nextSentence, previousSentence, returnToPosition
    case search, nextMatch, previousMatch
    case togglePanel, openDocument, openEditor
}

struct Shortcut: Identifiable {
    let id = UUID()
    let keyCode: Int
    let modifiers: Int
    let keys: String
    let title: String
    let action: ShortcutAction
}

/// Default global shortcuts. All use ⌃⌥ so they rarely clash with other apps.
enum Shortcuts {
    private static let ctrlOpt = controlKey | optionKey

    static let all: [Shortcut] = [
        Shortcut(keyCode: kVK_Space, modifiers: ctrlOpt, keys: "⌃⌥Space", title: "Play / pause", action: .togglePlay),
        Shortcut(keyCode: kVK_RightArrow, modifiers: ctrlOpt, keys: "⌃⌥→", title: "Faster", action: .faster),
        Shortcut(keyCode: kVK_LeftArrow, modifiers: ctrlOpt, keys: "⌃⌥←", title: "Slower", action: .slower),
        Shortcut(keyCode: kVK_DownArrow, modifiers: ctrlOpt, keys: "⌃⌥↓", title: "Next sentence", action: .nextSentence),
        Shortcut(keyCode: kVK_UpArrow, modifiers: ctrlOpt, keys: "⌃⌥↑", title: "Previous sentence", action: .previousSentence),
        Shortcut(keyCode: kVK_ANSI_R, modifiers: ctrlOpt, keys: "⌃⌥R", title: "Return to where I was", action: .returnToPosition),
        Shortcut(keyCode: kVK_ANSI_F, modifiers: ctrlOpt, keys: "⌃⌥F", title: "Search", action: .search),
        Shortcut(keyCode: kVK_ANSI_G, modifiers: ctrlOpt, keys: "⌃⌥G", title: "Next match", action: .nextMatch),
        Shortcut(keyCode: kVK_ANSI_G, modifiers: ctrlOpt | shiftKey, keys: "⌃⌥⇧G", title: "Previous match", action: .previousMatch),
        Shortcut(keyCode: kVK_ANSI_H, modifiers: ctrlOpt, keys: "⌃⌥H", title: "Show / hide prompter", action: .togglePanel),
        Shortcut(keyCode: kVK_ANSI_O, modifiers: ctrlOpt, keys: "⌃⌥O", title: "Open document", action: .openDocument),
        Shortcut(keyCode: kVK_ANSI_E, modifiers: ctrlOpt, keys: "⌃⌥E", title: "Edit script", action: .openEditor),
    ]
}

/// System-wide hotkeys via Carbon. Works while other apps are focused and
/// needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.fire(id) }
            }
            return noErr
        }, 1, &spec, selfPointer, nil)
    }

    func register(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E505254), id: id) // "NPRT"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            actions[id] = action
        } else {
            NSLog("NotchPrompter: could not register hotkey %d (status %d)", keyCode, status)
        }
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }
}
