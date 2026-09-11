import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let tracker = BackgroundLocationTracker()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    tracker.resumeIfNeeded()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    tracker.enterBackground()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "BackgroundLocationTracker"
    ) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "location_baohuo/background_location",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] (
      call: FlutterMethodCall,
      result: @escaping FlutterResult
    ) in
      guard let self = self else {
        result(FlutterError(
          code: "unavailable",
          message: "App delegate unavailable",
          details: nil
        ))
        return
      }
      switch call.method {
      case "status": result(self.tracker.status())
      case "start": self.tracker.start(result: result)
      case "stop": self.tracker.stop(); result(self.tracker.status())
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

private final class BackgroundLocationTracker: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let store = UserDefaults.standard
  private var timer: DispatchSourceTimer?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var permissionResult: FlutterResult?

  private let runningKey = "backgroundLocation.running"
  private let minuteCountKey = "backgroundLocation.minuteCount"
  private let tickDateKey = "backgroundLocation.lastTickDate"
  private let locationCountKey = "backgroundLocation.locationCount"
  private let locationDateKey = "backgroundLocation.locationDate"
  private let latitudeKey = "backgroundLocation.latitude"
  private let longitudeKey = "backgroundLocation.longitude"

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 100
    manager.allowsBackgroundLocationUpdates = true
    manager.pausesLocationUpdatesAutomatically = false
    manager.showsBackgroundLocationIndicator = true
  }

  func start(result: @escaping FlutterResult) {
    permissionResult = result
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestAlwaysAuthorization()
    case .authorizedAlways:
      beginLocationUpdates()
      finishPermissionRequest()
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
    default:
      result(FlutterError(
        code: "location_permission_denied",
        message: "请在系统设置中授予“始终允许”定位权限。",
        details: nil
      ))
      permissionResult = nil
    }
  }

  func stop() {
    manager.stopUpdatingLocation()
    timer?.cancel()
    timer = nil
    store.set(false, forKey: runningKey)
    endBackgroundTask()
  }

  // Core Location may relaunch the app for a location event after termination.
  func resumeIfNeeded() {
    guard store.bool(forKey: runningKey), manager.authorizationStatus == .authorizedAlways else {
      return
    }
    beginLocationUpdates()
  }

  // Gives the app a brief period to finish work while the location service is started.
  func enterBackground() {
    guard store.bool(forKey: runningKey) else { return }
    beginBackgroundTask()
    manager.startUpdatingLocation()
    startMinuteTimer()
    NSLog("[location_baohuo] background monitoring active")
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard permissionResult != nil else { return }
    if manager.authorizationStatus == .authorizedAlways {
      beginLocationUpdates()
      finishPermissionRequest()
    } else if manager.authorizationStatus != .notDetermined && manager.authorizationStatus != .authorizedWhenInUse {
      permissionResult?(FlutterError(
        code: "location_permission_denied",
        message: "需要“始终允许”定位权限。",
        details: nil
      ))
      permissionResult = nil
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    store.set(store.integer(forKey: locationCountKey) + 1, forKey: locationCountKey)
    store.set(location.timestamp.timeIntervalSince1970 * 1000, forKey: locationDateKey)
    store.set(location.coordinate.latitude, forKey: latitudeKey)
    store.set(location.coordinate.longitude, forKey: longitudeKey)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("Background location update failed: \(error.localizedDescription)")
  }

  func status() -> [String: Any] {
    [
      "running": store.bool(forKey: runningKey),
      "authorization": authorizationText(manager.authorizationStatus),
      "minuteCount": store.integer(forKey: minuteCountKey),
      "lastTickAt": store.double(forKey: tickDateKey),
      "locationEvents": store.integer(forKey: locationCountKey),
      "lastLocationAt": store.double(forKey: locationDateKey),
      "latitude": store.object(forKey: latitudeKey) ?? NSNull(),
      "longitude": store.object(forKey: longitudeKey) ?? NSNull(),
    ]
  }

  private func beginLocationUpdates() {
    store.set(true, forKey: runningKey)
    manager.startUpdatingLocation()
    startMinuteTimer()
  }

  private func startMinuteTimer() {
    guard timer == nil else { return }
    let newTimer = DispatchSource.makeTimerSource(queue: .main)
    newTimer.schedule(deadline: .now() + .seconds(60), repeating: .seconds(60))
    newTimer.setEventHandler { [weak self] in self?.recordMinuteTick() }
    timer = newTimer
    newTimer.resume()
  }

  private func recordMinuteTick() {
    store.set(store.integer(forKey: minuteCountKey) + 1, forKey: minuteCountKey)
    store.set(Date().timeIntervalSince1970 * 1000, forKey: tickDateKey)
    NSLog("[location_baohuo] background minute count = \(store.integer(forKey: minuteCountKey))")
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private func finishPermissionRequest() {
    permissionResult?(status())
    permissionResult = nil
  }

  private func authorizationText(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "未请求"
    case .restricted: return "受系统限制"
    case .denied: return "已拒绝"
    case .authorizedWhenInUse: return "仅使用期间"
    case .authorizedAlways: return "始终允许"
    @unknown default: return "未知"
    }
  }
}
