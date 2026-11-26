import Foundation

struct DayPlan: Codable {
    let athlete, date, title, intensity, reason, structure: String
    let athleteId, decisionId, decisionVersion, planVersion, timeZone: String
    let generatedAtMs, validUntilMs: Int64
    let minutes: Int
}

enum WatchDelivery {
    static func accepts(_ context: [String: Any], after last: Int64) -> Bool {
        guard context["schema"] as? Int == 2,
              let sequence = context["sequence"] as? Int64, sequence > last else { return false }
        return context["kind"] as? String == "clear" || decodePlan(context) != nil
    }
    static func decodePlan(_ context: [String: Any]) -> DayPlan? {
        guard context["schema"] as? Int == 2, context["kind"] as? String == "plan",
              let data = try? JSONSerialization.data(withJSONObject: context),
              let value = try? JSONDecoder().decode(DayPlan.self, from: data),
              value.decisionId == "\(value.athleteId)/\(value.date)",
              !value.athleteId.isEmpty, !value.decisionVersion.isEmpty else { return nil }
        return value
    }

}
