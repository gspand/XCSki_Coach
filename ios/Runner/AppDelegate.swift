import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, WCSessionDelegate {
  private let pendingKey = "xc.watch.outgoing.v2"
  private var channel: FlutterMethodChannel?

  override func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
    return super.application(application, didFinishLaunchingWithOptions: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    channel = FlutterMethodChannel(name: "at.skybase.xcski/watch", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel?.setMethodCallHandler { [weak self] call, reply in
      guard let self, call.method == "update", var value = call.arguments as? [String: Any],
            value["schema"] as? Int == 2, ["plan", "clear"].contains(value["kind"] as? String ?? "") else {
        reply(FlutterMethodNotImplemented)
        return
      }
      let defaults = UserDefaults.standard
      let last = defaults.dictionary(forKey: self.pendingKey)?["sequence"] as? Int64 ?? 0
      let sent = WCSession.isSupported() ? (WCSession.default.applicationContext["sequence"] as? Int64 ?? 0) : 0
      value["sequence"] = max(Int64(Date().timeIntervalSince1970 * 1000), max(last, sent) + 1)
      value["zoneIdentifier"] = TimeZone.current.identifier
      defaults.set(value, forKey: self.pendingKey)
      self.publish()
      reply(nil)
    }
  }

  private func publish() {
    guard WCSession.isSupported(), let pending = UserDefaults.standard.dictionary(forKey: pendingKey) else { return }
    let session = WCSession.default
    guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
    do { try session.updateApplicationContext(pending) }
    catch { NSLog("XC Coach: Watch-Übertragung ausstehend.") }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    publish()
  }
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    DispatchQueue.main.async { self.publish() }
  }
  func sessionWatchStateDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.publish() }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
