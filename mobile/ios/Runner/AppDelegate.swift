import native_video_player

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notification
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    SwiftNativeVideoPlayerPlugin.cookieStorage = URLSessionManager.cookieStorage
    URLSessionManager.patchBackgroundDownloader()
    BackgroundWorkerApiImpl.registerBackgroundWorkers()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    AppDelegate.registerPlugins(with: engineBridge.pluginRegistry, messenger: messenger)
  }

  public static func registerPlugins(with registry: FlutterPluginRegistry, messenger: FlutterBinaryMessenger) {
    NativeSyncApiImpl.register(with: registry.registrar(forPlugin: NativeSyncApiImpl.name)!)
    PermissionApiSetup.setUp(binaryMessenger: messenger, api: PermissionApiImpl())
    LocalImageApiSetup.setUp(binaryMessenger: messenger, api: LocalImageApiImpl())
    RemoteImageApiSetup.setUp(binaryMessenger: messenger, api: RemoteImageApiImpl())
    BackgroundWorkerFgHostApiSetup.setUp(binaryMessenger: messenger, api: BackgroundWorkerApiImpl())
    ConnectivityApiSetup.setUp(binaryMessenger: messenger, api: ConnectivityApiImpl())
    NetworkApiSetup.setUp(binaryMessenger: messenger, api: NetworkApiImpl())
    registerCustomClipboard(messenger: messenger)
  }

  /// Custom fork: copy a photo to the clipboard. Downloads the original with the app's own
  /// session (login cookies) so the Dart side only passes the URL.
  private static func registerCustomClipboard(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "immich.custom/clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "copyImageUrl",
            let args = call.arguments as? [String: Any],
            let link = args["url"] as? String,
            let url = URL(string: link) else {
        result(FlutterMethodNotImplemented)
        return
      }
      URLSessionManager.shared.session.dataTask(with: url) { data, response, error in
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let data = data, code == 200, let image = UIImage(data: data) else {
          DispatchQueue.main.async {
            result(FlutterError(code: "download", message: error?.localizedDescription ?? "Download failed (\(code))", details: nil))
          }
          return
        }
        DispatchQueue.main.async {
          UIPasteboard.general.image = image
          result(true)
        }
      }.resume()
    }
  }

  public static func cancelPlugins(with engine: FlutterEngine) {
    (engine.valuePublished(byPlugin: NativeSyncApiImpl.name) as? NativeSyncApiImpl)?.detachFromEngine()
  }
}
