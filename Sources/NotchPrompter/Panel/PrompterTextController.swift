import AppKit
import SwiftUI

/// Scroll view that reports when the person scrolls with trackpad/mouse.
final class PrompterScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}

/// Owns the AppKit text view that shows the document, and does all the
/// low-level scrolling and highlighting.
@MainActor
final class PrompterTextController {
    let scrollView = PrompterScrollView()
    let textView: NSTextView

    var onUserScroll: (() -> Void)?
    /// Called with the character index at the reading line (top line).
    var onReadingPositionChanged: ((Int) -> Void)?

    private let topPadding: CGFloat = 6
    private var font: NSFont = .systemFont(ofSize: 24, weight: .medium)
    private var baseColor: NSColor = .white
    private var dimOthers = true
    private var lineSpacing: CGFloat = 4
    private(set) var lineHeight: CGFloat = 32

    private var highlighted: NSRange?
    private var exactOffset: CGFloat = 0
    private var pendingAnimations = 0
    private var observers: [NSObjectProtocol] = []

    init() {
        textView = NSTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: topPadding)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        scrollView.onUserScroll = { [weak self] in self?.onUserScroll?() }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.boundsChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateInsets() }
        })
    }

    // MARK: - Content & style

    private var dimColor: NSColor { dimOthers ? baseColor.withAlphaComponent(0.4) : baseColor }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: dimColor, .paragraphStyle: paragraph]
    }

    func setText(_ text: String) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: baseAttributes))
        highlighted = nil
        ensureLayout()
    }

    func applyStyle(font: NSFont, color: NSColor, dimOthers: Bool, lineSpacing: CGFloat, lineHeight: CGFloat) {
        self.font = font
        self.baseColor = color
        self.dimOthers = dimOthers
        self.lineSpacing = lineSpacing
        self.lineHeight = lineHeight
        if let storage = textView.textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.addAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
        let current = highlighted
        highlighted = nil
        highlight(current)
        updateInsets()
    }

    /// Shows `range` at full brightness and dims the previous one.
    func highlight(_ range: NSRange?) {
        guard let storage = textView.textStorage else { return }
        let length = storage.length
        storage.beginEditing()
        if let old = highlighted, NSMaxRange(old) <= length {
            storage.addAttribute(.foregroundColor, value: dimColor, range: old)
        }
        if let new = range, NSMaxRange(new) <= length {
            storage.addAttribute(.foregroundColor, value: baseColor, range: new)
        }
        storage.endEditing()
        highlighted = range
    }

    func setSearchHighlights(_ ranges: [NSRange], current: Int?) {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
        for (index, range) in ranges.enumerated() where NSMaxRange(range) <= storage.length {
            let color = index == current
                ? NSColor.systemOrange.withAlphaComponent(0.85)
                : NSColor.systemYellow.withAlphaComponent(0.3)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }

    // MARK: - Geometry

    private func ensureLayout() {
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
    }

    /// Lets the last line scroll up to the reading line.
    private func updateInsets() {
        let bottom = max(0, scrollView.frame.height - lineHeight - topPadding)
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
    }

    private var usedHeight: CGFloat {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height
    }

    /// Offset at which the last line sits on the reading line.
    private var maxOffset: CGFloat { max(0, usedHeight - lineHeight) }

    /// Average vertical points per word, used to convert WPM to scroll speed.
    func pointsPerWord(wordCount: Int) -> CGFloat {
        guard wordCount > 0 else { return 0 }
        return usedHeight / CGFloat(wordCount)
    }

    /// Character index at the reading line (the top line, closest to the camera).
    func characterAtReadingLine() -> Int {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let storage = textView.textStorage, storage.length > 0 else { return 0 }
        let y = scrollView.contentView.bounds.origin.y + lineHeight * 0.5
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 1, y: max(0, y)), in: container)
        return min(layoutManager.characterIndexForGlyph(at: glyph), storage.length - 1)
    }

    // MARK: - Scrolling

    /// Moves the text up by `points`. Returns false once the end is reached.
    func scroll(by points: CGFloat) -> Bool {
        let clip = scrollView.contentView
        // Re-sync if something else (e.g. the person) moved the text.
        if abs(clip.bounds.origin.y - exactOffset) > 2 {
            exactOffset = clip.bounds.origin.y
        }
        let limit = maxOffset
        exactOffset = min(exactOffset + points, limit)
        clip.setBoundsOrigin(NSPoint(x: 0, y: exactOffset))
        scrollView.reflectScrolledClipView(clip)
        return exactOffset < limit - 0.5
    }

    /// Puts the line containing `index` on the reading line.
    func scroll(toCharacter index: Int, animated: Bool) {
        guard let layoutManager = textView.layoutManager,
              let storage = textView.textStorage, storage.length > 0 else { return }
        ensureLayout()
        let charIndex = min(max(0, index), storage.length - 1)
        let glyph = layoutManager.glyphIndexForCharacter(at: charIndex)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let target = min(max(0, lineRect.minY), maxOffset)
        exactOffset = target

        let clip = scrollView.contentView
        let origin = NSPoint(x: 0, y: target)
        if animated {
            pendingAnimations += 1
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(origin)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scrollView.reflectScrolledClipView(clip)
                    self.pendingAnimations -= 1
                }
            })
        } else {
            pendingAnimations += 1
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
            pendingAnimations -= 1
        }
    }

    private func boundsChanged() {
        // Programmatic jumps set the current sentence themselves.
        guard pendingAnimations == 0 else { return }
        onReadingPositionChanged?(characterAtReadingLine())
    }
}

struct PrompterTextRepresentable: NSViewRepresentable {
    let controller: PrompterTextController

    func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
