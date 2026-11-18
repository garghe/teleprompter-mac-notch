import SwiftUI
import AppKit

/// Window to write or paste a script and send it to the prompter.
struct EditorView: View {
    @ObservedObject var prompter: Prompter
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Open Document…") { prompter.openDocumentPanel() }
                Text(prompter.documentName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(stats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Send to Prompter") {
                    prompter.load(text: draft, name: prompter.documentName)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            Divider()
            ScriptTextEditor(text: $draft)
            Divider()
            Text("⌘F to search · ⌘↩ to send to the prompter · You can also drop a file on the prompter")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear { draft = prompter.document.text }
        .onReceive(prompter.$document) { draft = $0.text }
    }

    private var stats: String {
        let words = draft.split(whereSeparator: { $0.isWhitespace }).count
        let seconds = Int(Double(words) / max(prompter.wpm, 1) * 60)
        return "\(words) words · ~\(seconds / 60):\(String(format: "%02d", seconds % 60)) at \(Int(prompter.wpm)) wpm"
    }
}

/// Plain-text NSTextView with the native find bar (⌘F).
struct ScriptTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 15)
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptTextEditor
        init(_ parent: ScriptTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
