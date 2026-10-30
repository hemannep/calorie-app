import AVFoundation
import Flutter
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var pendingWidgetAction: String?
  private var activeAudioPlayers: [AVAudioPlayer] = []

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
      case "playSplashSound":
        let kind = (call.arguments as? String) ?? "chime"
        self?.playSplashTone(kind: kind)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func playSplashTone(kind: String) {
    DispatchQueue.global(qos: .userInteractive).async { [weak self] in
      let sampleRate = 24000
      let durationMs = kind == "tick" ? 28 : 520
      let numSamples = (sampleRate * durationMs) / 1000
      var pcm = [Int16](repeating: 0, count: numSamples)
      for i in 0..<numSamples {
        let t = Double(i) / Double(sampleRate)
        let sample: Double
        if kind == "tick" {
          let env = exp(-t * 140.0) * (1.0 - exp(-t * 900.0))
          sample = sin(2.0 * .pi * 520.0 * t) * env * 0.16
        } else {
          let note1Env = exp(-t * 9.5) * (1.0 - exp(-t * 260.0))
          let note1 = (sin(2.0 * .pi * 698.46 * t) + 0.35 * sin(2.0 * .pi * 1396.91 * t)) * note1Env
          let t2 = max(0.0, t - 0.085)
          let note2Env = t >= 0.085 ? exp(-t2 * 6.5) * (1.0 - exp(-t2 * 240.0)) : 0.0
          let note2 = (sin(2.0 * .pi * 880.0 * t2) + 0.45 * sin(2.0 * .pi * 1046.50 * t2)) * note2Env
          sample = (note1 * 0.45 + note2 * 0.55) * 0.22
        }
        let clamped = max(-1.0, min(1.0, sample))
        pcm[i] = Int16(clamped * Double(Int16.max))
      }
      let wavData = Self.makeWav(pcm: pcm, sampleRate: UInt32(sampleRate))
      DispatchQueue.main.async {
        guard let self = self else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        if let player = try? AVAudioPlayer(data: wavData) {
          player.prepareToPlay()
          player.play()
          self.activeAudioPlayers.append(player)
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.activeAudioPlayers.removeAll { !$0.isPlaying }
          }
        }
      }
    }
  }

  private static func makeWav(pcm: [Int16], sampleRate: UInt32) -> Data {
    let dataSize = UInt32(pcm.count * 2)
    let fileSize = 36 + dataSize
    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    var leFileSize = fileSize.littleEndian
    data.append(Data(bytes: &leFileSize, count: 4))
    data.append("WAVEfmt ".data(using: .ascii)!)
    var fmtChunkSize: UInt32 = 16.littleEndian
    var audioFormat: UInt16 = 1.littleEndian
    var numChannels: UInt16 = 1.littleEndian
    var leSampleRate = sampleRate.littleEndian
    var byteRate = (sampleRate * 2).littleEndian
    var blockAlign: UInt16 = 2.littleEndian
    var bitsPerSample: UInt16 = 16.littleEndian
    data.append(Data(bytes: &fmtChunkSize, count: 4))
    data.append(Data(bytes: &audioFormat, count: 2))
    data.append(Data(bytes: &numChannels, count: 2))
    data.append(Data(bytes: &leSampleRate, count: 4))
    data.append(Data(bytes: &byteRate, count: 4))
    data.append(Data(bytes: &blockAlign, count: 2))
    data.append(Data(bytes: &bitsPerSample, count: 2))
    data.append("data".data(using: .ascii)!)
    var leDataSize = dataSize.littleEndian
    data.append(Data(bytes: &leDataSize, count: 4))
    pcm.withUnsafeBufferPointer { ptr in
      data.append(UnsafeBufferPointer(start: UnsafeRawPointer(ptr.baseAddress)?.assumingMemoryBound(to: UInt8.self), count: Int(dataSize)))
    }
    return data
  }
}
