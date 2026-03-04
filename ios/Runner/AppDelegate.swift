import Flutter
import UIKit
import TorClient

@main
@objc class AppDelegate: FlutterAppDelegate {
  var torThread: TorThread?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let torChannel = FlutterMethodChannel(name: "onion_talkie/tor_ios",
                                          binaryMessenger: controller.binaryMessenger)
    
    torChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
              let torrcPath = args["torrcPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "torrcPath required", details: nil))
          return
        }
        
        if self.torThread != nil {
          result(true)
          return
        }
        
        let config = TorConfiguration()
        config.arguments = ["-f", torrcPath]
        
        self.torThread = TorThread(configuration: config)
        self.torThread?.start()
        result(true)
        
      case "stop":
        self.torThread?.cancel()
        self.torThread = nil
        result(true)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
