/// Master passphrases proposed at vault creation: words drawn uniformly from the EFF large list.
/// Six words from 7772 give about 77 bits, on top of the Argon2id cost of every guess.
public enum Passphrase {
    public static let wordCount = 6
    public static let separator = "-"
    public static var vocabularySize: Int { PassphraseWords.all.count }

    /// Draws with the system's cryptographic generator.
    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// `Int.random(in:using:)` draws without modulo bias; tests pass a seeded generator.
    static func generate(using generator: inout some RandomNumberGenerator) -> String {
        let words = PassphraseWords.all
        return (0..<wordCount).map { _ in words[Int.random(in: words.indices, using: &generator)] }.joined(separator: separator)
    }
}
