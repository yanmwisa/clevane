/// Site passwords proposed in Add Row: 20 characters drawn uniformly, with at least one lowercase letter,
/// one uppercase letter, one digit and one symbol, since many sites demand each. Draws that miss a class are
/// redrawn, which keeps every accepted password equally likely. About 125 bits.
public enum StrongPassword {
    public static let length = 20
    static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")
    static let symbols = Array("-_.!@#$%*+=?")
    static let classes = [lowercase, uppercase, digits, symbols]
    static let alphabet = classes.flatMap { $0 }

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate(using generator: inout some RandomNumberGenerator) -> String {
        while true {
            let candidate = (0..<length).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] }
            if classes.allSatisfy({ characterClass in candidate.contains(where: characterClass.contains) }) {
                return String(candidate)
            }
        }
    }
}
