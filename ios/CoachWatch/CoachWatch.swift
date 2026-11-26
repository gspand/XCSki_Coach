import SwiftUI
import WatchConnectivity

@main
struct CoachWatchApp: App {
    @StateObject private var model = WristPlan()
    var body: some Scene {
        WindowGroup {
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        if let plan = model.plan {
                            Text(plan.athlete).foregroundStyle(.mint)
                            if plan.date == Self.day(clock.date), clock.date.timeIntervalSince1970 * 1000 < Double(plan.validUntilMs) {
                                Text(plan.title).font(.headline)
                                if plan.minutes > 0 {
                                    Text("\(plan.minutes) min · \(plan.intensity)")
                                }
                                Text(plan.structure).font(.footnote)
                                Divider()
                                Text(plan.reason).font(.footnote)
                                Text("Stand \(Date(timeIntervalSince1970: Double(plan.generatedAtMs) / 1000), style: .time) · \(plan.timeZone)").font(.caption2)
                                Text("\(plan.decisionId) · \(plan.decisionVersion.prefix(10))").font(.caption2)
                            } else {
                                Text("Letzter Stand: \(plan.date)").font(.headline)
                                Text("Öffne den Coach auf dem iPhone für den aktuellen Trainingstag.")
                            }
                        } else {
                            Text("XC Ski Coach").font(.headline)
                            Text("Wähle im Profilmenü des iPhone-Coachs „Tagesplan auf die Uhr“.")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static func day(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

final class WristPlan: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var plan: DayPlan?
    override init() {
        super.init()
        UserDefaults.standard.removeObject(forKey: "dayPlan")
        if let stored = UserDefaults.standard.dictionary(forKey: "xc.watch.incoming.v2") {
            plan = WatchDelivery.decodePlan(stored)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        accept(session.receivedApplicationContext)
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }
    private func accept(_ context: [String: Any]) {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            let key = "xc.watch.incoming.v2"
            let previous = defaults.dictionary(forKey: key)?["sequence"] as? Int64 ?? 0
            guard WatchDelivery.accepts(context, after: previous) else { return }
            let value = WatchDelivery.decodePlan(context)
            defaults.set(context, forKey: key)
            self.plan = value
        }
    }
}
