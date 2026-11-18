import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private lazy var prompter = Prompter(settings: settings)
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        panel = PanelController(
            prompter: prompter,
            settings: settings,
            openEditor: { [weak self] in self?.openEditor() },
            hidePanel: { [weak self] in self?.panel.hide() }
        )
        buildStatusItem()
        registerHotKeys()
        panel.show()
        prompter.restoreLastSession()
    }

    // MARK: - Status bar menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Notch Prompter")

        let menu = NSMenu()
        menu.addItem(menuItem("Show / Hide Prompter  (⌃⌥H)", #selector(togglePanel)))
        menu.addItem(menuItem("Play / Pause  (⌃⌥Space)", #selector(togglePlay)))
        menu.addItem(menuItem("Search  (⌃⌥F)", #selector(showSearch)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Document…  (⌃⌥O)", #selector(openDocument)))
        menu.addItem(menuItem("Edit Script…  (⌃⌥E)", #selector(openEditor)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings & Shortcuts…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Notch Prompter", #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func togglePanel() { panel.toggle() }
    @objc private func togglePlay() { panel.show(); prompter.togglePlay() }
    @objc private func showSearch() { panel.show(); prompter.showSearch() }
    @objc private func openDocument() { panel.show(); prompter.openDocumentPanel() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func openEditor() {
        if editorWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: EditorView(prompter: prompter)))
            window.title = "Notch Prompter — Script"
            window.setContentSize(NSSize(width: 680, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            editorWindow = window
        }
        NSApp.activate()
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, prompter: prompter)))
            window.title = "Notch Prompter — Settings"
            window.styleMask.remove(.resizable)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Global shortcuts

    private func registerHotKeys() {
        for shortcut in Shortcuts.all {
            let action = shortcut.action
            HotKeyCenter.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                self?.run(action)
            }
        }
    }

    private func run(_ action: ShortcutAction) {
        switch action {
        case .togglePlay: panel.show(); prompter.togglePlay()
        case .faster: prompter.changeSpeed(by: 10)
        case .slower: prompter.changeSpeed(by: -10)
        case .nextSentence: prompter.nextSentence()
        case .previousSentence: prompter.previousSentence()
        case .returnToPosition: prompter.returnToLastPosition()
        case .search: panel.show(); prompter.toggleSearch()
        case .nextMatch: prompter.nextMatch()
        case .previousMatch: prompter.previousMatch()
        case .togglePanel: panel.toggle()
        case .openDocument: panel.show(); prompter.openDocumentPanel()
        case .openEditor: openEditor()
        }
    }

    // MARK: - Main menu (needed for copy/paste/find in the editor window)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Notch Prompter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let findNext = edit.addItem(withTitle: "Find Next", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g")
        findNext.tag = NSTextFinder.Action.nextMatch.rawValue
        let findPrev = edit.addItem(withTitle: "Find Previous", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g")
        findPrev.keyEquivalentModifierMask = [.command, .shift]
        findPrev.tag = NSTextFinder.Action.previousMatch.rawValue
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
