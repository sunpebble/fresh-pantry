import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Let the headless background isolate (the WorkManager outbox drain) register
    // the same plugins the app uses, so it can reach path_provider (Drift) and
    // Supabase. Must be set before any background task fires.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Register the periodic BGAppRefreshTask handler. The identifier must match
    // the Dart `backgroundSyncUniqueName` ("fresh_pantry.periodic_sync") and the
    // Info.plist BGTaskSchedulerPermittedIdentifiers entry; iOS requires all task
    // handlers to be registered before launch finishes.
    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: "fresh_pantry.periodic_sync",
        frequency: NSNumber(value: 15 * 60)
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
