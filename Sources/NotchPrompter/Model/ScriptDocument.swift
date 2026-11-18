import Foundation
import NaturalLanguage

/// The loaded text, split into sentences. Sentence indexes are shared by
/// scrolling, "return to position", search and (later) voice-follow.
struct ScriptDocument {
    let text: String
    let sentences: [NSRange]
    let wordCount: Int

    var length: Int { (text as NSString).length }

    init(text: String) {
        self.text = text
        var result: [NSRange] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result.append(NSRange(range, in: text))
            return true
        }
        if result.isEmpty {
            result = [NSRange(location: 0, length: (text as NSString).length)]
        }
        sentences = result
        wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Index of the sentence that contains (or last starts before) `location`.
    func sentenceIndex(containing location: Int) -> Int {
        var low = 0
        var high = sentences.count - 1
        var answer = 0
        while low <= high {
            let mid = (low + high) / 2
            if sentences[mid].location <= location {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    /// Case- and accent-insensitive search.
    func ranges(matching query: String) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let haystack = text as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let match = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            if match.location == NSNotFound { break }
            found.append(match)
            let next = match.location + max(match.length, 1)
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return found
    }
}
