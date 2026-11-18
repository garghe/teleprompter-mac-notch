import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PanelView: View {
    @ObservedObject var prompter: Prompter
    @ObservedObject var settings: Settings
    @ObservedObject var layout: PanelLayout
    let openEditor: () -> Void
    let hidePanel: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var dragStartLines: Int?

    private var showControls: Bool { prompter.isHovering || prompter.isSearchVisible }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: layout.topHeight)
                .overlay(alignment: .leading) {
                    if !settings.hideFromCapture {
                        // Always-visible reminder that the panel can be captured.
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .padding(.leading, 12)
                            .help("Visible in screenshots and screen sharing")
                    }
                }
            ZStack {
                PrompterTextRepresentable(controller: prompter.textController)
                overlays
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) { resizeHandle }
            if prompter.isSearchVisible {
                searchBar
                    .frame(height: PanelController.searchBarHeight)
            }
        }
        .background(Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { prompter.loadFile(url) }
            }
            return true
        }
        .onChange(of: prompter.isSearchVisible) { _, visible in
            if visible { DispatchQueue.main.async { searchFocused = true } }
        }
    }

    // Controls sit either side of the camera; they appear on hover.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                IconButton(symbol: prompter.isPlaying || prompter.countdown != nil ? "pause.fill" : "play.fill",
                           help: "Play / pause (⌃⌥Space)") { prompter.togglePlay() }
                IconButton(symbol: "minus", help: "Slower (⌃⌥←)") { prompter.changeSpeed(by: -10) }
                Text("\(Int(prompter.wpm)) wpm")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize()
                IconButton(symbol: "plus", help: "Faster (⌃⌥→)") { prompter.changeSpeed(by: 10) }
            }
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: layout.notchWidth)

            HStack(spacing: 10) {
                IconButton(symbol: "chevron.up", help: "Previous sentence (⌃⌥↑)") { prompter.previousSentence() }
                IconButton(symbol: "chevron.down", help: "Next sentence (⌃⌥↓)") { prompter.nextSentence() }
                IconButton(symbol: "arrow.uturn.backward", help: "Return to where I was (⌃⌥R)",
                           enabled: prompter.returnPoint != nil) { prompter.returnToLastPosition() }
                IconButton(symbol: "magnifyingglass", help: "Search (⌃⌥F)") { prompter.toggleSearch() }
                IconButton(symbol: "square.and.pencil", help: "Edit script (⌃⌥E)") { openEditor() }
                IconButton(symbol: "eye.slash", help: "Hide (⌃⌥H)") { hidePanel() }
            }
            .frame(maxWidth: .infinity)
        }
        .opacity(showControls ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: showControls)
    }

    /// Grip at the bottom edge: drag down/up to show more/fewer lines.
    /// Snaps to whole lines, between Settings.lineRange (3–20).
    private var resizeHandle: some View {
        Capsule()
            .fill(Color.white.opacity(dragStartLines != nil ? 0.7 : 0.35))
            .frame(width: 44, height: 4)
            .frame(maxWidth: 120, minHeight: 12)
            .contentShape(Rectangle())
            .opacity(showControls || dragStartLines != nil ? 1 : 0)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartLines ?? settings.visibleLines
                        if dragStartLines == nil { dragStartLines = start }
                        let delta = Int((value.translation.height / settings.lineHeight).rounded())
                        let lines = Settings.clampLines(start + delta)
                        if lines != settings.visibleLines { settings.visibleLines = lines }
                    }
                    .onEnded { _ in
                        dragStartLines = nil
                        prompter.showToast("\(settings.visibleLines) lines")
                    }
            )
            .help("Drag to resize (\(Settings.lineRange.lowerBound)–\(Settings.lineRange.upperBound) lines)")
    }

    @ViewBuilder
    private var overlays: some View {
        if prompter.document.wordCount == 0 {
            Text("Drop a document here, or press ⌃⌥E to write a script")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .allowsHitTesting(false)
        }
        if let count = prompter.countdown {
            Text("\(count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.75))
                .allowsHitTesting(false)
        }
        if let toast = prompter.toast {
            VStack {
                Spacer()
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                    .padding(.bottom, 6)
            }
            .allowsHitTesting(false)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField("Search document", text: $prompter.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onSubmit { prompter.nextMatch() }
                .onExitCommand { prompter.hideSearch() }
            Text(matchLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize()
            IconButton(symbol: "chevron.up", help: "Previous match (⌃⌥⇧G)") { prompter.previousMatch() }
            IconButton(symbol: "chevron.down", help: "Next match (⌃⌥G / Return)") { prompter.nextMatch() }
            IconButton(symbol: "xmark", help: "Close search (Esc)") { prompter.hideSearch() }
        }
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.08))
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private var matchLabel: String {
        if prompter.searchQuery.isEmpty { return "" }
        if prompter.matches.isEmpty { return "No matches" }
        return "\(prompter.matchIndex + 1)/\(prompter.matches.count)"
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
        .disabled(!enabled)
        .help(help)
    }
}
