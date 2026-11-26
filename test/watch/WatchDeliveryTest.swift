import Foundation

@main
enum WatchDeliveryTest {
    static func main() {
        let clear: [String: Any] = ["schema": 2, "sequence": 5 as Int64, "kind": "clear"]
        var plan: [String: Any] = [
            "schema": 2, "kind": "plan", "sequence": 4 as Int64,
            "athlete": "Test", "athleteId": "test", "date": "2026-11-26",
            "decisionId": "test/2026-11-26", "decisionVersion": "sample", "planVersion": "sample",
            "timeZone": "CET", "generatedAtMs": 1000, "validUntilMs": 2000,
            "title": "Ruhetag", "minutes": 0, "intensity": "", "reason": "", "structure": ""
        ]
        precondition(WatchDelivery.accepts(plan, after: 3))
        precondition(WatchDelivery.accepts(clear, after: 4))
        precondition(!WatchDelivery.accepts(plan, after: 5))
        precondition(!WatchDelivery.accepts(clear, after: 5))
        precondition(WatchDelivery.decodePlan(clear) == nil)
        let restored = try! PropertyListSerialization.propertyList(
          from: PropertyListSerialization.data(fromPropertyList: plan, format: .binary, options: 0),
          options: [], format: nil) as! [String: Any]
        precondition(WatchDelivery.accepts(restored, after: 3))
        plan["athleteId"] = "another"
        precondition(!WatchDelivery.accepts(plan, after: 3))
        plan.removeValue(forKey: "schema")
        precondition(!WatchDelivery.accepts(plan, after: 0))
        print("Watch envelope passed ordering, revocation, restoration and identity checks")
    }
}
