import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var prompter: Prompter

    var body: some View {
        Form {
            Section("Text") {
                Slider(value: $settings.fontSize, in: 14...48, step: 1) {
                    Text("Font size: \(Int(settings.fontSize))")
                }
                Stepper("Visible lines: \(settings.visibleLines)", value: $settings.visibleLines, in: 1...10)
                Picker("Colour", selection: $settings.textColor) {
                    ForEach(TextColorOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Toggle("Dim everything except the current sentence", isOn: $settings.dimOtherSentences)
            }
            Section("Panel") {
                Slider(value: $settings.panelWidth, in: 400...1200, step: 10) {
                    Text("Width: \(Int(settings.panelWidth))")
                }
                Text("The panel is hidden from screen sharing and recordings. Check it once with your own video tool before an important call.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Scrolling") {
                Slider(value: $prompter.wpm, in: 40...400, step: 10) {
                    Text("Speed: \(Int(prompter.wpm)) words/min")
                }
                Toggle("3-second countdown before scrolling", isOn: $settings.countdownEnabled)
            }
            Section("Keyboard shortcuts (work in any app)") {
                ForEach(Shortcuts.all) { shortcut in
                    HStack {
                        Text(shortcut.title)
                        Spacer()
                        Text(shortcut.keys)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}
