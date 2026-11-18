import AppKit

enum TextColorOption: String, CaseIterable, Identifiable {
    case white, yellow, green, cyan

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .white: return .white
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.45, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.6, green: 1.0, blue: 0.65, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.55, green: 0.9, blue: 1.0, alpha: 1)
        }
    }
}

/// User preferences, saved in UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: "panelWidth") } }
    @Published var visibleLines: Int { didSet { defaults.set(visibleLines, forKey: "visibleLines") } }
    @Published var textColor: TextColorOption { didSet { defaults.set(textColor.rawValue, forKey: "textColor") } }
    @Published var dimOtherSentences: Bool { didSet { defaults.set(dimOtherSentences, forKey: "dimOthers") } }
    @Published var countdownEnabled: Bool { didSet { defaults.set(countdownEnabled, forKey: "countdown") } }
    /// Keeps the panel out of screenshots, recordings and screen sharing.
    @Published var hideFromCapture: Bool { didSet { defaults.set(hideFromCapture, forKey: "hideFromCapture") } }

    init() {
        defaults.register(defaults: [
            "fontSize": 24.0,
            "panelWidth": 640.0,
            "visibleLines": 3,
            "textColor": TextColorOption.white.rawValue,
            "dimOthers": true,
            "countdown": true,
            "wpm": 140.0,
            "hideFromCapture": true,
        ])
        fontSize = defaults.double(forKey: "fontSize")
        panelWidth = defaults.double(forKey: "panelWidth")
        visibleLines = defaults.integer(forKey: "visibleLines")
        textColor = TextColorOption(rawValue: defaults.string(forKey: "textColor") ?? "") ?? .white
        dimOtherSentences = defaults.bool(forKey: "dimOthers")
        countdownEnabled = defaults.bool(forKey: "countdown")
        hideFromCapture = defaults.bool(forKey: "hideFromCapture")
    }

    var font: NSFont { .systemFont(ofSize: CGFloat(fontSize), weight: .medium) }
    var lineSpacing: CGFloat { CGFloat(fontSize) * 0.2 }
    var lineHeight: CGFloat { NSLayoutManager().defaultLineHeight(for: font) + lineSpacing }
}
