import Foundation
import Supabase

/// Keeps database encoding and conditional writes behind the grocery transport seam.
@MainActor
struct SupabaseGroceryTransport: GrocerySyncTransport {
    func fetch(householdID: UUID) async throws -> [GroceryItem] {
        var rows: [GroceryItemRecord] = []
        var cursor: UUID?
        let pageSize = 500
        while true {
            try Task.checkCancellation()
            var query = supabase.from("grocery_items").select().eq("household_id", value: householdID)
            if let cursor { query = query.gt("id", value: cursor) }
            let page: [GroceryItemRecord] = try await query.order("id").limit(pageSize).execute().value
            rows.append(contentsOf: page)
            guard page.count == pageSize, let last = page.last else { return rows.map(GroceryItem.init) }
            cursor = last.id
        }
    }

    func write(_ mutation: GroceryMutation, householdID: UUID) async throws {
        switch mutation {
        case .insert(let items):
            try await supabase.from("grocery_items").insert(items.map { $0.record(household: householdID) }).execute()
        case let .edit(id, fields):
            try await supabase.from("grocery_items").update(fields)
                .eq("household_id", value: householdID).eq("id", value: id).execute()
        case .delete(let ids):
            try await supabase.from("grocery_items").delete()
                .eq("household_id", value: householdID).in("id", values: ids).execute()
        case .reorder(let positions):
            let params = GroceryOrderParameters(target_household: householdID,
                item_ids: positions.map(\.id), item_positions: positions.map(\.value))
            try await supabase.rpc("reorder_groceries", params: params).execute()
        case .sort(let assignments):
            let groups = Dictionary(grouping: assignments, by: \.value)
            for (aisle, assignments) in groups {
                try Task.checkCancellation()
                // A rename or another shopper's classification must win over a stale result.
                try await supabase.from("grocery_items").update(["aisle": aisle])
                    .eq("household_id", value: householdID).is("aisle", value: nil)
                    .in("name", values: Array(Set(assignments.map(\.name)))).execute()
            }
        }
    }
}
