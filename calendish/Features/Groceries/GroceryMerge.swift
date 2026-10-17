import Foundation

/// Combines grocery lines for the same food, such as "1 onion" for one recipe and "2 onions" for another,
/// into one item ("3 onions") that lists both recipes as sources.
///
/// Lines combine when they name the same food in the same unit. Lines without any amount, such as
/// "Salt to taste", combine with each other. Ranges like "2–3 onions", and amounts in different units, stay apart.
enum GroceryMerge {
    private struct Key: Hashable {
        let food: String
        /// The unit with any package size, "" for counted foods, or nil when the line has no amount.
        let unit: String?
    }

    private struct Member {
        let text: String
        let quantity: Double?
    }

    /// Adds `lines`, in order, to `groceries`, combining lines with each other and with unchecked items already on the list.
    static func plan(_ lines: [(text: String, source: String)], into groceries: [GroceryItem]) -> GroceryImport {
        var groups: [(key: Key?, members: [Member], sources: [String], existing: GroceryItem?)] = []
        var claimed: Set<UUID> = []
        for line in lines {
            let measured = measure(line.text)
            let member = Member(text: line.text, quantity: measured?.quantity)
            if let key = measured?.key, let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].members.append(member)
                groups[index].sources.append(line.source)
                continue
            }
            let existing = measured.flatMap { measured in
                groceries.first { !$0.isComplete && !claimed.contains($0.id) && measure(GroceryFood.text(of: $0))?.key == measured.key }
            }
            if let existing {
                claimed.insert(existing.id)
                let quantity = measure(GroceryFood.text(of: existing))?.quantity
                groups.append((measured?.key, [Member(text: GroceryFood.text(of: existing), quantity: quantity), member],
                    existing.sources + [line.source], existing))
            } else {
                groups.append((measured?.key, [member], [line.source], nil))
            }
        }

        var result = GroceryImport()
        let start = (groceries.map(\.position).max() ?? 0) + 1
        for group in groups {
            let name = group.members.count == 1 ? group.members[0].text : combined(group.members, unit: group.key?.unit)
            var item = group.existing ?? GroceryItem(name: name, amount: "", source: "",
                position: start + Double(result.added.count))
            item.sources = combinedSources(group.sources)
            if let original = group.existing {
                item.name = name
                item.amount = ""
                if item.name != original.name || item.source != original.source {
                    result.updated.append((item, original))
                }
            } else {
                result.added.append(item)
            }
        }
        return result
    }

    /// Each source once, in order. "General" only stands in when no recipe needs the item.
    private static func combinedSources(_ sources: [String]) -> [String] {
        var unique: [String] = []
        for source in sources where !unique.contains(source) { unique.append(source) }
        let recipes = unique.filter { $0 != "General" }
        return recipes.isEmpty ? unique : recipes
    }

    /// The food and unit a line can combine by, with its amount. Nil for lines that never combine:
    /// ranges, amounts the parser can't read, and lines that don't name a food.
    private static func measure(_ line: String) -> (key: Key, quantity: Double?)? {
        let food = IngredientParser.foodKey(of: line)
        guard !food.isEmpty else { return nil }
        guard let range = IngredientParser.amountRange(in: line) else {
            return line.contains(where: \.isNumber) ? nil : (Key(food: food, unit: nil), nil)
        }
        let amount = line[range]
        let number = amount.prefix { $0.isNumber || " /.,".contains($0) }
        let unitText = amount.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        guard !unitText.contains(where: \.isNumber), !unitText.hasPrefix("-"), !unitText.hasPrefix("–"),
              let quantity = Ingredient.quantity(number.trimmingCharacters(in: .whitespaces)) else { return nil }
        // A package size, as in "1 (15 oz) can", is part of the unit.
        let size = line.firstMatch(of: #/\([^)]*\)/#).map { " " + $0.output.lowercased() } ?? ""
        return (Key(food: food, unit: canonicalUnit(unitText) + size), quantity)
    }

    private static let unitAliases = [
        "teaspoon": "tsp", "tablespoon": "tbsp", "tb": "tbsp", "tbs": "tbsp", "fluid ounce": "fl oz", "c": "cup",
        "pint": "pt", "quart": "qt", "gallon": "gal", "ounce": "oz", "pound": "lb", "lbs": "lb",
        "milliliter": "ml", "millilitre": "ml", "liter": "l", "litre": "l", "kilogram": "kg", "kilo": "kg",
        "gram": "g", "package": "pkg",
    ]

    private static func canonicalUnit(_ unit: String) -> String {
        let words = unit.lowercased().replacingOccurrences(of: ".", with: "").split(separator: " ").map(String.init)
        guard let last = words.last else { return "" }
        let singular = (words.dropLast() + [IngredientParser.singular(of: last)]).joined(separator: " ")
        return unitAliases[singular] ?? singular
    }

    /// One line for members that share a food and unit: the total amount, written like the member with the
    /// largest amount, without preparation notes that may differ between recipes.
    private static func combined(_ members: [Member], unit: String?) -> String {
        guard unit != nil, let representative = members.max(by: { ($0.quantity ?? 0) < ($1.quantity ?? 0) }),
              let quantity = representative.quantity, quantity > 0 else { return members[0].text }
        let total = members.reduce(0) { $0 + ($1.quantity ?? 0) }
        var line = Ingredient.scale(representative.text, by: total / quantity)
        let name = IngredientParser.name(of: line)
        if !name.isEmpty, let amount = IngredientParser.amountRange(in: line),
           let found = line.range(of: name, range: amount.upperBound..<line.endIndex) {
            line = String(line[..<found.upperBound])
            // "1 onion" twice is "2 onions"; a measured amount like "2 cup milk" keeps its food as written.
            if unit == "", total > 1, quantity <= 1,
               let lastWord = line.lastIndex(where: \.isWhitespace).map({ line.index(after: $0) }) {
                line = String(line[..<lastWord]) + IngredientParser.plural(of: String(line[lastWord...]))
            }
        }
        return line
    }
}
