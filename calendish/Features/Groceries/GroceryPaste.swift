import Foundation

/// Keeps quantities and punctuation intact while removing common copied-list markers.
enum GroceryPaste {
    static func items(from text: String) -> [GroceryItem] {
        text.components(separatedBy: .newlines).compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: #"^(?:[-*•‣▪☐☑✓✔](?:\s+|$)|\d+[.)]\s+)?(?:\[[ xX]\]\s*)?"#,
                                      with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return GroceryItem(name: name, amount: "", source: "General")
        }
    }
}
