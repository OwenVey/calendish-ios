import Foundation

/// Reads ingredient lines as written, such as "1 cup unsalted butter, softened", to find the amount
/// at the front and the food it names, then finds those foods mentioned in recipe steps.
nonisolated enum IngredientParser {
    /// Measures and counted containers that can follow a quantity. Matched case-insensitively at a word boundary.
    private static let units = [
        "teaspoons", "teaspoon", "tsp.", "tsp", "tablespoons", "tablespoon", "tbsp.", "tbsp", "tbs",
        "fluid ounces", "fluid ounce", "fl. oz.", "fl. oz", "fl oz", "cups", "cup", "c.",
        "pints", "pint", "pt", "quarts", "quart", "qt", "gallons", "gallon", "gal",
        "ounces", "ounce", "oz.", "oz", "pounds", "pound", "lbs.", "lbs", "lb.", "lb",
        "milliliters", "millilitres", "milliliter", "millilitre", "ml", "liters", "litres", "liter", "litre", "l",
        "dl", "cl", "kilograms", "kilogram", "kilos", "kilo", "kg", "grams", "gram", "g", "mg",
        "pinches", "pinch", "dashes", "dash", "drops", "drop", "handfuls", "handful",
        "cloves", "clove", "cans", "can", "jars", "jar", "bottles", "bottle", "packages", "package", "pkg", "packets", "packet",
        "sticks", "stick", "bunches", "bunch", "sprigs", "sprig", "heads", "head", "stalks", "stalk",
        "slices", "slice", "pieces", "piece", "fillets", "fillet", "sheets", "sheet", "bags", "bag", "boxes", "box",
    ].sorted { $0.count > $1.count }

    /// Words that name a part or cut of a food rather than the food, so "garlic cloves" is also found as
    /// "garlic" and "chicken thighs" as "chicken".
    private static let partWords: Set = [
        "clove", "cloves", "leaf", "leaves", "sprig", "sprigs", "stalk", "stalks", "head", "heads", "bulb", "bulbs",
        "floret", "florets", "ear", "ears", "fillet", "fillets", "filet", "filets", "thigh", "thighs", "breast", "breasts",
        "wing", "wings", "drumstick", "drumsticks", "leg", "legs", "tenders", "tenderloin", "tenderloins", "loin",
        "chop", "chops", "steak", "steaks", "cutlet", "cutlets", "rib", "ribs", "shank", "shanks", "strips",
    ]

    /// Words describing how a food is bought or prepared. Alone they don't name an ingredient, and a
    /// comma after them doesn't end the name, as in "boneless, skinless chicken breasts".
    private static let descriptors: Set = [
        "boneless", "skinless", "bone-in", "skin-on", "fresh", "freshly", "dried", "frozen", "thawed", "large", "medium",
        "small", "extra", "extra-large", "jumbo", "whole", "raw", "cooked", "uncooked", "ripe", "packed", "lightly",
        "firmly", "loosely", "heaping", "level", "chopped", "finely", "roughly", "coarsely", "thinly", "minced", "diced",
        "sliced", "grated", "shredded", "crushed", "melted", "softened", "cold", "warm", "hot", "room-temperature",
        "peeled", "seeded", "trimmed", "halved", "quartered", "organic", "low-sodium", "unsalted", "salted", "plain",
    ]

    /// Words that can't begin a name in a step, so "salt and pepper" isn't found as "and pepper".
    private static let joiningWords: Set = ["and", "or", "&", "of", "with", "in", "plus", "to"]

    /// Words too general to stand for an ingredient alone; "garlic powder" isn't found as just "powder".
    private static let vagueWords: Set = [
        "powder", "juice", "sauce", "paste", "leaves", "seeds", "mix", "zest", "extract", "flakes", "stock",
        "broth", "spray", "mixture", "dressing", "filling", "topping", "glaze", "pieces", "chunks", "cubes",
    ]

    private static let quantity = #"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?(?:\s?[¼½¾⅓⅔⅛⅜⅝⅞])?|[¼½¾⅓⅔⅛⅜⅝⅞])"#
    private static let amountPattern = try! Regex(#"^\s*"# + quantity + #"(?:\s*(?:[-–]|to)\s*"# + quantity + ")?")

    /// The leading amount in a line, including its unit when it has one: "1½ cups" in "1½ cups orzo", or "2" in "2 large eggs".
    static func amountRange(in line: String) -> Range<String.Index>? {
        guard let match = line.prefixMatch(of: amountPattern) else { return nil }
        let number = match.range
        let rest = line[number.upperBound...]
        let afterSpace = rest.drop { $0 == " " }
        guard let unitLength = unitLength(at: afterSpace) else {
            // "2 large eggs": keep any digits glued to letters, like "2x", out of the amount.
            if let next = rest.first, next.isLetter { return nil }
            return trimmed(number, in: line)
        }
        return trimmed(number.lowerBound..<line.index(afterSpace.startIndex, offsetBy: unitLength), in: line)
    }

    /// The food a line names: "unsalted butter" from "1 cup unsalted butter, softened".
    static func name(of line: String) -> String {
        var text = line.replacing(#/\([^)]*\)/#, with: "")
        if let amount = amountRange(in: text) { text.removeSubrange(..<amount.upperBound) }
        // Notes follow a comma, as in "butter, softened", but leading descriptions don't end the name.
        let segments = text.split(whereSeparator: { ",;:".contains($0) }).map(String.init)
        text = segments.first { segment in
            !segment.split(whereSeparator: \.isWhitespace).allSatisfy { descriptors.contains($0.lowercased()) }
        } ?? segments.first ?? ""
        for phrase in [" to taste", " for ", " plus ", " - ", " – ", " such as "] {
            if let range = text.range(of: phrase, options: .caseInsensitive) { text = String(text[..<range.lowerBound]) }
        }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        // Unit words left at the front when there was no number, as in "Pinch of salt", or after a parenthetical size.
        while let first = words.first, unitLength(at: Substring(first)) == first.count || first.lowercased() == "of" {
            words.removeFirst()
        }
        return words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
    }

    /// Ingredients mentioned in a step: each range in `step` with the indexes of the `ingredients` it could mean.
    /// Longer names win, so "brown sugar" is one mention rather than also matching "sugar".
    static func mentions(in step: String, ingredients: [String]) -> [(range: Range<String.Index>, ingredients: [Int])] {
        var phrases: [String: [Int]] = [:]
        for (index, line) in ingredients.enumerated() {
            for phrase in searchPhrases(for: name(of: line)) where phrases[phrase]?.contains(index) != true {
                phrases[phrase, default: []].append(index)
            }
        }
        var found: [(range: Range<String.Index>, ingredients: [Int])] = []
        for (phrase, indexes) in phrases.sorted(by: { $0.key.count > $1.key.count }) {
            var searchStart = step.startIndex
            while let range = step.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<step.endIndex) {
                searchStart = range.upperBound
                let before = range.lowerBound > step.startIndex ? step[step.index(before: range.lowerBound)] : " "
                let after = range.upperBound < step.endIndex ? step[range.upperBound] : " "
                guard !before.isLetter, !after.isLetter, !found.contains(where: { $0.range.overlaps(range) }) else { continue }
                found.append((range, indexes))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Lowercased ways a step might refer to a food: the whole name, its trailing words ("butter" for
    /// "unsalted butter"), each side of "and"/"or", and singular and plural forms.
    static func searchPhrases(for name: String) -> Set<String> {
        let lowered = name.lowercased()
        guard !lowered.isEmpty else { return [] }
        var parts = [lowered]
        for separator in [" and ", " or ", " & ", "/"] {
            parts += parts.flatMap { $0.components(separatedBy: separator) }
        }
        var phrases: Set<String> = []
        for part in parts {
            var words = part.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            var wordLists = [words]
            if words.count > 1, partWords.contains(words.last!) {
                words.removeLast()
                wordLists.append(words)
            }
            for words in wordLists {
                for start in words.indices {
                    let suffix = Array(words[start...])
                    if joiningWords.contains(suffix[0]) { continue }
                    if suffix.count == 1, suffix[0].count < 3 || vagueWords.contains(suffix[0]) || descriptors.contains(suffix[0]) { continue }
                    let head = suffix.dropLast().joined(separator: " ")
                    for form in forms(of: suffix.last!) {
                        phrases.insert(head.isEmpty ? form : head + " " + form)
                    }
                }
            }
        }
        return phrases
    }

    /// The word with its likely singular or plural partner: "eggs" and "egg", "berry" and "berries".
    private static func forms(of word: String) -> [String] {
        guard word.count > 2, word.allSatisfy(\.isLetter) else { return [word] }
        if word.hasSuffix("ies") { return [word, String(word.dropLast(3)) + "y"] }
        if word.hasSuffix("oes") || word.hasSuffix("shes") || word.hasSuffix("ches") { return [word, String(word.dropLast(2)), String(word.dropLast())] }
        if word.hasSuffix("ss") { return [word, word + "es"] }
        if word.hasSuffix("s") { return [word, String(word.dropLast())] }
        if word.hasSuffix("y"), let beforeY = word.dropLast().last, !"aeiou".contains(beforeY) { return [word, String(word.dropLast()) + "ies"] }
        if word.hasSuffix("o") || word.hasSuffix("sh") || word.hasSuffix("ch") { return [word, word + "es", word + "s"] }
        return [word, word + "s"]
    }

    private static func unitLength(at text: Substring) -> Int? {
        let lowered = text.lowercased()
        for unit in units where lowered.hasPrefix(unit) {
            let next = lowered.dropFirst(unit.count).first
            if let next, next.isLetter { continue }
            return unit.count
        }
        return nil
    }

    private static func trimmed(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var lower = range.lowerBound
        while lower < range.upperBound, line[lower].isWhitespace { lower = line.index(after: lower) }
        return lower..<range.upperBound
    }
}
