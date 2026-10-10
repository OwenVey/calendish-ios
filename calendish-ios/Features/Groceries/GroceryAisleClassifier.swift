import Foundation
import FoundationModels

/// Sorts grocery items into store aisles with no input from the shopper.
/// Uses the on-device language model when it's available and common keywords otherwise,
/// remembering each answer so an item added again is sorted instantly.
enum GroceryAisleClassifier {
    private static let cacheKey = "groceryAisleCache"
    private static let batchSize = 20

    /// The aisle for each of the given names, keyed by the name exactly as passed in.
    static func aisles(for names: [String]) async -> [String: GroceryAisle] {
        var cache = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        var result: [String: GroceryAisle] = [:]
        var unsorted: [String] = []
        for name in names {
            if let raw = cache[GroceryAisle.normalized(name)], let aisle = GroceryAisle(rawValue: raw) { result[name] = aisle }
            else { unsorted.append(name) }
        }
        guard !unsorted.isEmpty else { return result }
        var sorted: [String: GroceryAisle] = [:]
        if SystemLanguageModel.default.isAvailable {
            for start in stride(from: 0, to: unsorted.count, by: batchSize) {
                let batch = Array(unsorted[start..<min(start + batchSize, unsorted.count)])
                do {
                    sorted.merge(try await sortWithModel(batch)) { $1 }
                } catch is CancellationError {
                    break
                } catch {
                    // A guardrail or a busy model: the keywords below cover this batch.
                }
            }
        }
        for name in unsorted {
            // Only the model's answers are remembered, so a later attempt can improve on a keyword guess.
            if let aisle = sorted[name] { cache[GroceryAisle.normalized(name)] = aisle.rawValue }
            result[name] = sorted[name] ?? GroceryAisle.guess(for: name)
        }
        if cache.count > 2000 { cache = [:] }
        UserDefaults.standard.set(cache, forKey: cacheKey)
        return result
    }

    // MARK: On-device model

    @Generable
    nonisolated struct SortedItems {
        @Guide(description: "Every item from the list, once each, in the same order.")
        var items: [SortedItem]
    }

    @Generable
    nonisolated struct SortedItem {
        @Guide(description: "The item's name exactly as written in the list.")
        var name: String
        @Guide(description: "The aisle the item is found in.", .anyOf(GroceryAisle.allCases.map(\.rawValue)))
        var aisle: String
    }

    private static func sortWithModel(_ names: [String]) async throws -> [String: GroceryAisle] {
        let aisles = GroceryAisle.allCases.map { "- \($0.rawValue): \($0.examples)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            Sort grocery list items into the supermarket aisle where most stores shelve them. \
            Judge by the whole name: "peanut butter" goes in condiments, "chicken broth" in canned, \
            "frozen peas" in frozen, and "almond milk" in dairy. The aisles are:
            \(aisles)
            """)
        let list = names.map { "- \($0)" }.joined(separator: "\n")
        let response = try await session.respond(to: "Grocery list:\n\(list)", generating: SortedItems.self,
                                                 options: GenerationOptions(samplingMode: .greedy))
        let items = response.content.items
        var result: [String: GroceryAisle] = [:]
        let byName = Dictionary(items.map { (GroceryAisle.normalized($0.name), $0.aisle) }, uniquingKeysWith: { first, _ in first })
        for (index, name) in names.enumerated() {
            // Match by name, falling back to position when the model rewrote a name but kept the order.
            let raw = byName[GroceryAisle.normalized(name)] ?? (items.count == names.count ? items[index].aisle : nil)
            if let raw, let aisle = GroceryAisle(rawValue: raw) { result[name] = aisle }
        }
        return result
    }
}
