import AppKit
import Combine

/// The prompter's brain: document, play/pause, speed, reading position,
/// "return to where I was", and search. UI and hotkeys only call into this.
@MainActor
final class Prompter: ObservableObject, ScrollDriverDelegate {
    @Published private(set) var document = ScriptDocument(text: "")
    @Published private(set) var documentName = "Untitled"
    @Published private(set) var isPlaying = false
    @Published private(set) var countdown: Int?
    @Published var wpm: Double { didSet { UserDefaults.standard.set(wpm, forKey: "wpm") } }
    @Published private(set) var currentSentence = 0
    /// Sentence to jump back to after scrolling back to re-read.
    @Published private(set) var returnPoint: Int?
    @Published private(set) var isSearchVisible = false
    @Published var searchQuery = "" { didSet { if searchQuery != oldValue { runSearch() } } }
    @Published private(set) var matches: [NSRange] = []
    @Published private(set) var matchIndex = 0
    @Published private(set) var toast: String?
    @Published var isHovering = false

    let settings: Settings
    let textController = PrompterTextController()
    var onSearchVisibilityChanged: ((Bool) -> Void)?

    private var driver: ScrollDriver
    private var countdownTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    init(settings: Settings) {
        self.settings = settings
        self.wpm = UserDefaults.standard.double(forKey: "wpm")
        let timed = TimedScrollDriver()
        self.driver = timed
        timed.delegate = self
        timed.pointsPerSecond = { [weak self] in self?.pointsPerSecond ?? 0 }
        textController.onUserScroll = { [weak self] in self?.userScrolled() }
        textController.onReadingPositionChanged = { [weak self] in self?.readingPositionChanged($0) }
        applyStyle()
    }

    private var pointsPerSecond: CGFloat {
        CGFloat(wpm / 60) * textController.pointsPerWord(wordCount: document.wordCount)
    }

    // MARK: - Documents

    func restoreLastSession() {
        if let saved = Storage.load(), !saved.text.isEmpty {
            load(text: saved.text, name: saved.name, persist: false)
        } else {
            load(text: Self.welcomeText, name: "Welcome", persist: false)
        }
        let saved = UserDefaults.standard.integer(forKey: "lastSentence")
        if saved > 0, saved < document.sentences.count {
            // Wait for the panel's first layout pass.
            DispatchQueue.main.async { self.goToSentence(saved, animated: false) }
        }
    }

    func load(text: String, name: String, persist: Bool = true) {
        pause()
        document = ScriptDocument(text: text)
        documentName = name
        currentSentence = 0
        returnPoint = nil
        textController.setText(text)
        textController.highlight(document.sentences.first)
        textController.scroll(toCharacter: 0, animated: false)
        UserDefaults.standard.set(0, forKey: "lastSentence")
        if isSearchVisible { runSearch() }
        if persist { Storage.save(text: text, name: name) }
    }

    func loadFile(_ url: URL) {
        do {
            let text = try DocumentLoader.loadText(from: url)
            load(text: text, name: url.lastPathComponent)
            showToast("Loaded \(url.lastPathComponent)")
        } catch {
            showToast("Can't open \(url.lastPathComponent)")
        }
    }

    func openDocumentPanel() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentLoader.supportedTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a script or document (txt, md, rtf, docx, pdf, html)"
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url)
        }
    }

    // MARK: - Style

    func applyStyle() {
        textController.applyStyle(
            font: settings.font,
            color: settings.textColor.color,
            dimOthers: settings.dimOtherSentences,
            lineSpacing: settings.lineSpacing,
            lineHeight: settings.lineHeight
        )
    }

    /// Re-positions the current sentence after the layout changed.
    func realign() {
        guard document.sentences.indices.contains(currentSentence) else { return }
        textController.scroll(toCharacter: document.sentences[currentSentence].location, animated: false)
    }

    // MARK: - Play / pause / speed

    func togglePlay() {
        if isPlaying || countdown != nil { pause() } else { play() }
    }

    func play() {
        guard !isPlaying, countdownTask == nil, document.wordCount > 0 else { return }
        if settings.countdownEnabled {
            countdownTask = Task {
                for n in [3, 2, 1] {
                    self.countdown = n
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                }
                self.countdown = nil
                self.countdownTask = nil
                self.startScrolling()
            }
        } else {
            startScrolling()
        }
    }

    private func startScrolling() {
        isPlaying = true
        driver.start()
    }

    func pause() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
        driver.stop()
        isPlaying = false
    }

    func changeSpeed(by delta: Double) {
        wpm = min(400, max(40, wpm + delta))
        showToast("\(Int(wpm)) words/min")
    }

    // MARK: - ScrollDriverDelegate

    func scrollDriver(scrollBy points: CGFloat) {
        if !textController.scroll(by: points) {
            pause()
            showToast("End of document")
        }
    }

    func scrollDriver(moveToCharacter index: Int) {
        textController.scroll(toCharacter: index, animated: true)
        setCurrent(document.sentenceIndex(containing: index))
    }

    // MARK: - Reading position

    private func readingPositionChanged(_ character: Int) {
        let index = document.sentenceIndex(containing: character)
        if index != currentSentence { setCurrent(index) }
    }

    private func setCurrent(_ index: Int) {
        guard document.sentences.indices.contains(index) else { return }
        currentSentence = index
        textController.highlight(document.sentences[index])
        UserDefaults.standard.set(index, forKey: "lastSentence")
        // Once you're past the bookmark again, it's no longer needed.
        if let mark = returnPoint, index > mark { returnPoint = nil }
    }

    /// Remembers where you were before moving away (only the first time).
    private func markDeparture() {
        if returnPoint == nil { returnPoint = currentSentence }
    }

    private func userScrolled() {
        if isPlaying || countdown != nil { pause() }
        markDeparture()
    }

    func nextSentence() {
        goToSentence(currentSentence + 1, animated: true)
    }

    func previousSentence() {
        markDeparture()
        goToSentence(currentSentence - 1, animated: true)
    }

    func returnToLastPosition() {
        guard let mark = returnPoint else {
            showToast("Already at the latest point")
            return
        }
        returnPoint = nil
        goToSentence(mark, animated: true)
    }

    private func goToSentence(_ index: Int, animated: Bool) {
        guard !document.sentences.isEmpty else { return }
        let target = min(max(0, index), document.sentences.count - 1)
        setCurrent(target)
        textController.scroll(toCharacter: document.sentences[target].location, animated: animated)
    }

    // MARK: - Search

    func showSearch() {
        guard !isSearchVisible else {
            onSearchVisibilityChanged?(true) // re-focus the field
            return
        }
        isSearchVisible = true
        onSearchVisibilityChanged?(true)
        runSearch()
    }

    func hideSearch() {
        guard isSearchVisible else { return }
        isSearchVisible = false
        searchQuery = ""
        matches = []
        textController.setSearchHighlights([], current: nil)
        onSearchVisibilityChanged?(false)
    }

    func toggleSearch() {
        if isSearchVisible { hideSearch() } else { showSearch() }
    }

    private func runSearch() {
        matches = document.ranges(matching: searchQuery)
        matchIndex = 0
        textController.setSearchHighlights(matches, current: matches.isEmpty ? nil : 0)
        if !matches.isEmpty { jumpToMatch(0) }
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        jumpToMatch((matchIndex + 1) % matches.count)
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        jumpToMatch((matchIndex - 1 + matches.count) % matches.count)
    }

    private func jumpToMatch(_ index: Int) {
        matchIndex = index
        textController.setSearchHighlights(matches, current: index)
        if isPlaying || countdown != nil { pause() }
        markDeparture()
        let location = matches[index].location
        setCurrent(document.sentenceIndex(containing: location))
        textController.scroll(toCharacter: location, animated: true)
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }

    static let welcomeText = """
    Welcome to Notch Prompter. This text sits right under your camera, so you can read while looking at the lens. \
    Press Control Option Space to start or pause scrolling. \
    Use Control Option Left and Right arrows to change the speed. \
    Use Control Option Up and Down arrows to move one sentence at a time. \
    Scroll back with the trackpad to re-read, then press Control Option R to return to where you were. \
    Press Control Option F to search the document. \
    Press Control Option O to open a document, or Control Option E to write your own script. \
    You can also drop a file onto this panel. \
    Hover over the panel to see the controls.
    """
}
