package fm.chordia.mobile

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity, not FlutterActivity: it keeps the Flutter engine attached to the running
// audio service, so the activity can be destroyed and recreated without tearing down playback.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Dart owns the downloading; this only starts and stops the foreground service that keeps
        // the process alive while it happens.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fm.chordia.mobile/downloads",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val done = call.argument<Int>("done") ?: 0
                    val total = call.argument<Int>("total") ?: 0
                    DownloadService.update(applicationContext, done, total)
                    result.success(null)
                }
                "stop" -> {
                    DownloadService.stop(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
