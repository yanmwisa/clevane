import Foundation
import Testing
@testable import VaultCore

struct PassphraseTests {
    /// The EFF list minus its four hyphenated words, so "-" only ever separates words.
    @Test func vocabularyIsTheEFFListWithoutHyphens() {
        let words = PassphraseWords.all
        #expect(words.count == 7772)
        #expect(Set(words).count == words.count)
        #expect(words.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLowercase && $0.isLetter } })
        #expect(words.first == "abacus")
        #expect(words.last == "zoom")
    }

    @Test func sixWordsFromTheList() {
        let passphrase = Passphrase.generate()
        let words = passphrase.split(separator: Passphrase.separator).map(String.init)
        #expect(words.count == Passphrase.wordCount)
        #expect(words.allSatisfy(Set(PassphraseWords.all).contains))
    }

    /// The draw only depends on the generator it is given: the same seed gives the same phrase.
    @Test func drawFollowsTheInjectedGenerator() {
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        var other = SplitMix64(seed: 43)
        let phrase = Passphrase.generate(using: &first)
        #expect(phrase == Passphrase.generate(using: &second))
        #expect(phrase != Passphrase.generate(using: &other))
    }

    /// Two system draws in a row are different: a stuck or constant generator would show here.
    @Test func systemDrawsDiffer() {
        let draws = Set((0..<20).map { _ in Passphrase.generate() })
        #expect(draws.count == 20)
    }

    /// About 77 bits: enough on top of Argon2id (256 MiB, 3 passes per guess).
    @Test func strength() {
        let bits = Double(Passphrase.wordCount) * log2(Double(Passphrase.vocabularySize))
        #expect(bits > 77)
    }
}

/// Small deterministic generator (SplitMix64), to pin the draw in tests.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

struct StrongPasswordTests {
    @Test func everyClassIsPresentAndLengthIsFixed() {
        for _ in 0..<200 {
            let password = StrongPassword.generate()
            #expect(password.count == StrongPassword.length)
            #expect(StrongPassword.classes.allSatisfy { characterClass in password.contains(where: characterClass.contains) })
            #expect(password.allSatisfy(StrongPassword.alphabet.contains))
        }
    }

    /// Look-alike characters (0, O, 1, l, I) are left out so a password can be read aloud or retyped.
    @Test func noLookAlikes() {
        #expect(!StrongPassword.alphabet.contains { "0O1lI".contains($0) })
        #expect(Set(StrongPassword.alphabet).count == StrongPassword.alphabet.count)
    }

    @Test func systemDrawsDiffer() {
        #expect(Set((0..<20).map { _ in StrongPassword.generate() }).count == 20)
    }
}
