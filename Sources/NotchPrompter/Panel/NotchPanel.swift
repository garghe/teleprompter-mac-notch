import AppKit
import SwiftUI
import Combine

/// Borderless panel that floats above everything, on every Space and over
/// full-screen apps, without stealing focus from the app you're using.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        // Out of screen sharing, recordings and screenshots by default;
        // PanelController applies the user's "Hide from screen capture" setting.
        sharingType = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow the panel to sit over the menu bar / notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view that reports hover and accepts the first click.
final class HoverHostingView: NSHostingView<AnyView> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

/// Notch size of the screen the panel lives on.
struct NotchInfo {
    let screen: NSScreen
    let hasNotch: Bool
    let notchWidth: CGFloat
    let topHeight: CGFloat

    static func current() -> NotchInfo {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return NotchInfo(
                screen: screen,
                hasNotch: true,
                notchWidth: screen.frame.width - left.width - right.width,
                topHeight: screen.safeAreaInsets.top
            )
        }
        // No notch (external display): same panel at the top centre.
        return NotchInfo(screen: screen, hasNotch: false, notchWidth: 0, topHeight: NSStatusBar.system.thickness)
    }
}

@MainActor
final class PanelLayout: ObservableObject {
    @Published var notchWidth: CGFloat = 0
    @Published var topHeight: CGFloat = 32
}

/// Creates, sizes and positions the notch panel.
@MainActor
final class PanelController {
    static let searchBarHeight: CGFloat = 34

    let panel = NotchPanel()
    let layout = PanelLayout()
    private let prompter: Prompter
    private let settings: Settings
    private var cancellables = Set<AnyCancellable>()
    private var previousApp: NSRunningApplication?
    private(set) var isVisible = false

    init(prompter: Prompter, settings: Settings, openEditor: @escaping () -> Void, hidePanel: @escaping () -> Void) {
        self.prompter = prompter
        self.settings = settings

        let root = PanelView(prompter: prompter, settings: settings, layout: layout, openEditor: openEditor, hidePanel: hidePanel)
        let host = HoverHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.onHoverChange = { [weak prompter] hovering in prompter?.isHovering = hovering }
        panel.contentView = host

        prompter.onSearchVisibilityChanged = { [weak self] visible in self?.searchVisibilityChanged(visible) }

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.settingsChanged() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.relayout(realign: true) }
            }
            .store(in: &cancellables)

        applyCaptureSetting()
        relayout(realign: false)
    }

    func show() {
        guard !isVisible else { return }
        relayout(realign: false)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        prompter.pause()
        prompter.hideSearch()
        panel.orderOut(nil)
        isVisible = false
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    private func applyCaptureSetting() {
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
    }

    private func settingsChanged() {
        applyCaptureSetting()
        relayout(realign: false)
        prompter.applyStyle()
        DispatchQueue.main.async { self.prompter.realign() }
    }

    func relayout(realign: Bool) {
        let info = NotchInfo.current()
        layout.notchWidth = info.notchWidth
        layout.topHeight = info.topHeight

        let minWidth = info.notchWidth + 2 * 170
        let width = min(max(CGFloat(settings.panelWidth), minWidth), info.screen.frame.width)
        // Never taller than ~85% of the screen (e.g. 20 lines at a big font).
        let maxTextHeight = info.screen.frame.height * 0.85 - info.topHeight
        let textHeight = min(CGFloat(Settings.clampLines(settings.visibleLines)) * settings.lineHeight + 16, maxTextHeight)
        let height = info.topHeight + textHeight + (prompter.isSearchVisible ? Self.searchBarHeight : 0)
        let screenFrame = info.screen.frame
        let frame = NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
        panel.setFrame(frame, display: true)

        if realign {
            DispatchQueue.main.async { self.prompter.realign() }
        }
    }

    private func searchVisibilityChanged(_ visible: Bool) {
        relayout(realign: false)
        if visible {
            if !isVisible { show() }
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApp = front
            }
            // Non-activating panel: takes the keyboard for typing without
            // switching away from Zoom/Teams.
            panel.makeKey()
        } else {
            // Give the keyboard back to the app you were using.
            panel.orderOut(nil)
            if isVisible { panel.orderFrontRegardless() }
            previousApp?.activate(options: [])
            previousApp = nil
        }
    }
}
