package dev.frameforge.frameforge

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.media3.common.util.UnstableApi

@UnstableApi
class MainActivity : FlutterActivity() {
    private var videoEngine: VideoEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoEngine = VideoEngine(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        videoEngine?.dispose()
        super.onDestroy()
    }
}
