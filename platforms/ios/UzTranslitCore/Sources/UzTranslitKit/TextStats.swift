/// Character and word counts shown under each text pane.
public struct TextStats: Equatable, Sendable {
    /// User-perceived characters (grapheme clusters).
    public let characters: Int
    /// Runs of non-whitespace (JavaScript's \s plus the C0 controls, as the web app counts).
    public let words: Int

    public init(characters: Int, words: Int) {
        self.characters = characters
        self.words = words
    }

    public init(_ text: String) {
        var words = 0
        var inWord = false
        for u in text.utf16 {
            let space = TextStats.isSpace(u)
            if !space && !inWord { words += 1 }
            inWord = !space
        }
        self.init(characters: text.count, words: words)
    }

    public static let empty = TextStats(characters: 0, words: 0)

    static func isSpace(_ c: UInt16) -> Bool {
        c <= 0x20 || c == 0xA0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029
            || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF
    }
}
