import Flutter
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var pendingWidgetAction: String?

  func receiveWidgetURL(_ url: URL) {
    guard url.scheme == "kayleo", url.host == "widget" else { return }
    let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard ["photo", "voice", "barcode", "today", "streak"].contains(action) else { return }
    pendingWidgetAction = action
    widgetChannel?.invokeMethod("onAction", arguments: action)
  }
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "kayleo/home_widgets",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    widgetChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getInitialAction":
        result(self?.pendingWidgetAction)
        self?.pendingWidgetAction = nil
      case "update":
        guard let values = call.arguments as? [String: Any],
              let defaults = UserDefaults(suiteName: "group.com.rajendrapoudel.kayleo") else {
          result(FlutterError(code: "widget_storage", message: "Widget sharing is unavailable", details: nil))
          return
        }
        values.forEach { defaults.set($0.value, forKey: $0.key) }
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
