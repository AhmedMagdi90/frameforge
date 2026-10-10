package dev.frameforge.frameforge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.RectF
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.GlMatrixTransformation
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.SpeedChangeEffect
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import kotlin.math.min
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.roundToLong

@UnstableApi
class VideoEngine(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "dev.frameforge/video")
    private val events = EventChannel(messenger, "dev.frameforge/export")
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var sink: EventChannel.EventSink? = null
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private var outputPath: String? = null
    private var disposed = false

    init { methods.setMethodCallHandler(this); events.setStreamHandler(this) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspect" -> inspect(call, result)
            "inspectAudio" -> inspectAudio(call, result)
            "export" -> export(call, result)
            "cancelExport" -> { cancel(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun inspectAudio(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) { result.error("bad_arguments", "Missing audio path", null); return }
        worker.execute {
            val extractor = MediaExtractor()
            val retriever = MediaMetadataRetriever()
            try {
                extractor.setDataSource(path)
                require((0 until extractor.trackCount).any {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                }) { "The file contains no audio track" }
                retriever.setDataSource(path)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
                require(duration >= 100) { "This audio is too short or unreadable" }
                handler.post { if (!disposed) result.success(mapOf("durationMs" to duration)) }
            } catch (error: Exception) {
                handler.post { if (!disposed) result.error("inspect_audio_failed", error.message, null) }
            } finally { extractor.release(); retriever.release() }
        }
    }

    private fun inspect(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val thumbnailPath = call.argument<String>("thumbnailPath")
        if (path == null || thumbnailPath == null) {
            result.error("bad_arguments", "Missing media paths", null); return
        }
        worker.execute {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L
                val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toInt() ?: 0
                val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toInt() ?: 0
                require(duration >= 100 && width > 0 && height > 0) { "The file contains no playable video" }
                val frame = retriever.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 360, 360)
                val savedThumbnail = frame?.let {
                    File(thumbnailPath).outputStream().use { stream -> it.compress(Bitmap.CompressFormat.JPEG, 82, stream) }
                    it.recycle()
                    thumbnailPath
                }
                handler.post { if (!disposed) result.success(mapOf("durationMs" to duration,
                    "width" to width, "height" to height, "thumbnailPath" to savedThumbnail)) }
            } catch (error: Exception) {
                handler.post { if (!disposed) result.error("inspect_failed", error.message, null) }
            } finally { retriever.release() }
        }
    }

    private fun export(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) { result.error("busy", "An export is already running", null); return }
        try {
            val args = call.arguments as? Map<*, *> ?: error("Missing export arguments")
            val clips = (args["clips"] as? List<*>)?.map { it as Map<*, *> } ?: error("Missing clips")
            require(clips.isNotEmpty()) { "Add video clips before exporting" }
            val width = (args["width"] as Number).toInt()
            val height = (args["height"] as Number).toInt()
            require(width in 1..3840 && height in 1..3840 && width % 2 == 0 && height % 2 == 0)
            val fps = (args["fps"] as? Number)?.toInt() ?: 30
            require(fps in listOf(24, 30, 60)) { "Unsupported frame rate" }
            val path = args["outputPath"] as String
            require(!File(path).exists()) { "Output already exists" }
            val texts = (args["texts"] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
            val images = (args["images"] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
            require(images.size <= 20) { "Use up to 20 image overlays" }
            val intervals = mutableListOf<Segment>()
            var offset = 0L
            val items = clips.mapIndexed { index, clip ->
                val source = clip["path"] as String
                require(File(source).isFile) { "A source video is missing" }
                val start = (clip["startMs"] as Number).toLong()
                val end = (clip["endMs"] as Number).toLong()
                require(start >= 0 && end - start >= 100)
                val speed = ((clip["renderSpeed"] ?: clip["speed"]) as? Number)?.toFloat() ?: 1f
                require(speed.isFinite() && speed > 0 && speed <= 4.1f) { "Invalid clip speed" }
                val durationMs = (clip["outputDurationMs"] as? Number)?.toLong() ?: ((end - start) / speed).roundToLong()
                require(durationMs > 0)
                val duration = durationMs * 1000
                intervals.add(Segment(offset, duration,
                    index > 0 && clips[index - 1]["transition"] == "fade",
                    index < clips.lastIndex && clip["transition"] == "fade"))
                offset += duration
                val media = MediaItem.Builder().setUri(Uri.fromFile(File(source)))
                    .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(start).setEndPositionMs(end).build()).build()
                val videoEffects = mutableListOf<Effect>()
                val audioEffects = mutableListOf<AudioProcessor>()
                if (speed != 1f) {
                    videoEffects.add(SpeedChangeEffect(speed))
                    audioEffects.add(SonicAudioProcessor().apply { setSpeed(speed); setPitch(1f) })
                }
                val clipVolume = (clip["volume"] as? Number)?.toFloat() ?: 1f
                require(clipVolume.isFinite() && clipVolume in 0f..1f) { "Invalid clip volume" }
                if (clipVolume != 1f) audioEffects.add(GainProcessor(clipVolume))
                val matrix = (clip["filterMatrix"] as? List<*>)?.map { (it as Number).toFloat() }
                if (matrix != null) {
                    require(matrix.size == 20 && matrix.all { it.isFinite() }) { "Invalid filter matrix" }
                    videoEffects.add(ClipColorMatrix(matrix))
                }
                videoEffects.add(Presentation.createForWidthAndHeight(width, height,
                    if (clip["fit"] == "fill") Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP else Presentation.LAYOUT_SCALE_TO_FIT))
                EditedMediaItem.Builder(media)
                    .setRemoveAudio(clip["muted"] == true)
                    .setEffects(Effects(audioEffects, videoEffects))
                    .build()
            }
            val sequences = mutableListOf(EditedMediaItemSequence.Builder(items).build())
            val audioTracks = (args["audioTracks"] as? List<*>)?.map { it as Map<*, *> }
                ?: listOfNotNull(args["music"] as? Map<*, *>)
            require(audioTracks.size <= 8 && audioTracks.sumOf { (it["segments"] as? List<*>)?.size ?: 0 } <= 4000) {
                "Use up to eight audio tracks and choose longer looping sections"
            }
            for (music in audioTracks) {
                val musicSegments = (music["segments"] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
                if (musicSegments.isEmpty()) continue
                val source = music["path"] as String
                require(File(source).isFile) { "An audio file is missing" }
                val volume = (music["volume"] as Number).toFloat()
                require(volume.isFinite() && volume in 0f..1f) { "Invalid audio volume" }
                require(musicSegments.size <= 2000) { "Choose a longer music section or turn off looping" }
                val musicStart = (music["renderStartMs"] as Number).toLong()
                val musicEnd = (music["renderEndMs"] as Number).toLong()
                val fadeIn = (music["renderFadeInMs"] as Number).toLong()
                val fadeOut = (music["renderFadeOutMs"] as Number).toLong()
                val sequence = EditedMediaItemSequence.Builder()
                if (musicStart > 0) sequence.addGap(musicStart * 1000)
                var cursorMs = musicStart
                for (segment in musicSegments) {
                    val sourceStart = (segment["sourceStartMs"] as Number).toLong()
                    val sourceEnd = (segment["sourceEndMs"] as Number).toLong()
                    val startMs = (segment["timelineStartMs"] as Number).toLong()
                    val endMs = (segment["timelineEndMs"] as Number).toLong()
                    require(startMs == cursorMs && sourceEnd > sourceStart && endMs - startMs == sourceEnd - sourceStart)
                    val media = MediaItem.Builder().setUri(Uri.fromFile(File(source)))
                        .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(sourceStart).setEndPositionMs(sourceEnd).build()).build()
                    sequence.addItem(EditedMediaItem.Builder(media).setRemoveVideo(true)
                        .setEffects(Effects(listOf(GainProcessor(volume, startMs, musicStart, musicEnd, fadeIn, fadeOut)), emptyList())).build())
                    cursorMs = endMs
                }
                if (cursorMs * 1000 < offset) sequence.addGap(offset - cursorMs * 1000)
                sequences.add(sequence.build())
            }
            val compositionEffects = mutableListOf<Effect>(FrameDropEffect.createDefaultFrameDropEffect(fps.toFloat()),
                TimelineMotion(clips, intervals, width, height), TimelineFade(intervals))
            if (texts.isNotEmpty() || images.isNotEmpty()) {
                compositionEffects.add(OverlayEffect(ImmutableList.of(TimedSceneBitmap(texts, images, width, height))))
            }
            val composition = Composition.Builder(sequences)
                .experimentalSetForceAudioTrack(true)
                .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
                .setEffects(Effects(emptyList(), compositionEffects)).build()
            outputPath = path
            pending = result
            transformer = Transformer.Builder(context)
                .setVideoMimeType(MimeTypes.VIDEO_H264).setAudioMimeType(MimeTypes.AUDIO_AAC)
                .setEncoderFactory(DefaultEncoderFactory.Builder(context).setEnableFallback(false).build())
                .addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        sink?.success(1.0)
                        val savedPath = outputPath
                        val callback = clear()
                        callback?.success(savedPath)
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                        outputPath?.let { File(it).delete() }
                        val callback = clear()
                        callback?.error("export_failed", exportException.message, exportException.errorCode)
                    }
                }).build()
            transformer!!.start(composition, path)
            handler.post(progress)
        } catch (error: Exception) {
            transformer?.cancel()
            outputPath?.let { File(it).delete() }
            clear()
            result.error("export_failed", error.message, null)
        }
    }

    private val progress = object : Runnable {
        override fun run() {
            val exporter = transformer ?: return
            val holder = ProgressHolder()
            if (exporter.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                sink?.success(holder.progress / 100.0)
            }
            handler.postDelayed(this, 200)
        }
    }

    private fun clear(): MethodChannel.Result? {
        handler.removeCallbacks(progress)
        val callback = pending
        transformer = null; pending = null; outputPath = null
        return callback
    }
    private fun cancel() {
        transformer?.cancel()
        outputPath?.let { File(it).delete() }
        clear()?.error("export_cancelled", "Export cancelled", null)
    }
    fun dispose() {
        cancel(); disposed = true; worker.shutdown()
        methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null
    }
}

private data class Segment(val startUs: Long, val durationUs: Long, val fadeIn: Boolean, val fadeOut: Boolean)

@UnstableApi
private class ClipColorMatrix(matrix: List<Float>) : RgbMatrix {
    // Flutter uses row-major 4×5 RGBA matrices; OpenGL uses column-major 4×4.
    // All presets preserve alpha. Normalize the RGB offsets to [0, 1].
    private val values = floatArrayOf(
        matrix[0], matrix[5], matrix[10], 0f,
        matrix[1], matrix[6], matrix[11], 0f,
        matrix[2], matrix[7], matrix[12], 0f,
        matrix[4] / 255f, matrix[9] / 255f, matrix[14] / 255f, 1f
    )
    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray = values
}

@UnstableApi
private class TimelineFade(private val segments: List<Segment>) : RgbMatrix {
    override fun getMatrix(presentationTimeUs: Long, useHdr: Boolean): FloatArray {
        val segment = segments.firstOrNull { presentationTimeUs >= it.startUs && presentationTimeUs < it.startUs + it.durationUs }
        var brightness = 1f
        if (segment != null) {
            val local = presentationTimeUs - segment.startUs
            val fade = min(300_000L, segment.durationUs / 2).toFloat()
            if (segment.fadeIn) brightness = min(brightness, local / fade)
            if (segment.fadeOut) brightness = min(brightness, (segment.durationUs - local) / fade)
        }
        // RGB multiplication fades the footage to black before text is composited.
        return FloatArray(16).also {
            Matrix.setIdentityM(it, 0)
            it[0] = brightness.coerceIn(0f, 1f); it[5] = it[0]; it[10] = it[0]
        }
    }
}

@UnstableApi
private class TimedSceneBitmap(private val texts: List<Map<*, *>>, private val images: List<Map<*, *>>, private val width: Int,
    private val height: Int) : BitmapOverlay() {
    private val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    private var lastActive: List<Map<*, *>>? = null
    private var lastImages: List<Map<*, *>>? = null
    private val assets = images.map { it["path"] as String }.distinct().associateWith { path ->
        BitmapFactory.decodeFile(path) ?: error("An overlay image is missing or unreadable")
    }

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val timeMs = presentationTimeUs / 1000
        val active = texts.filter { timeMs >= (it["startMs"] as Number).toLong() && timeMs < (it["endMs"] as Number).toLong() }
        val activeImages = images.filter { timeMs >= (it["startMs"] as Number).toLong() && timeMs < (it["endMs"] as Number).toLong() }
        if (active == lastActive && activeImages == lastImages) return bitmap
        lastActive = active; lastImages = activeImages
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
        for (image in activeImages) {
            val asset = assets.getValue(image["path"] as String)
            val imageWidth = width * (image["width"] as Number).toFloat()
            val imageHeight = imageWidth / (image["aspect"] as Number).toFloat()
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                alpha = ((image["opacity"] as Number).toFloat().coerceIn(0f, 1f) * 255).toInt()
            }
            canvas.save()
            canvas.translate(width * (image["x"] as Number).toFloat(), height * (image["y"] as Number).toFloat())
            canvas.rotate((image["rotation"] as Number).toFloat())
            canvas.drawBitmap(asset, null, RectF(-imageWidth / 2, -imageHeight / 2, imageWidth / 2, imageHeight / 2), paint)
            canvas.restore()
        }
        for (text in active) {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = (text["color"] as Number).toLong().toInt()
                textSize = height * (text["size"] as Number).toFloat()
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                setShadowLayer(4f, 0f, 1f, Color.BLACK)
            }
            val textWidth = (width * .84f).toInt()
            val value = text["text"] as String
            val layout = StaticLayout.Builder.obtain(value, 0, value.length, paint, textWidth)
                .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(false)
                .setLineSpacing(0f, 1.15f).build()
            canvas.save()
            canvas.translate((width - textWidth) / 2f,
                height * (text["y"] as Number).toFloat() - layout.height / 2f)
            layout.draw(canvas); canvas.restore()
        }
        return bitmap
    }

    override fun release() { super.release(); bitmap.recycle(); assets.values.forEach { it.recycle() } }
}

@UnstableApi
private class TimelineMotion(clips: List<Map<*, *>>, private val segments: List<Segment>,
    width: Int, height: Int) : GlMatrixTransformation {
    private val motions = clips.map { clip -> ClipMotion(clip, width, height,
        (clip["startMs"] as Number).toLong(),
        ((clip["renderSpeed"] ?: clip["speed"]) as? Number)?.toFloat() ?: 1f) }
    override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray {
        val index = segments.indexOfFirst { presentationTimeUs >= it.startUs && presentationTimeUs < it.startUs + it.durationUs }
        if (index < 0) return FloatArray(16).also { Matrix.setIdentityM(it, 0) }
        return motions[index].getGlMatrixArray(presentationTimeUs - segments[index].startUs)
    }
}

@UnstableApi
private class ClipMotion(clip: Map<*, *>, private val width: Int, private val height: Int,
    private val sourceStartMs: Long, private val speed: Float) : GlMatrixTransformation {
    private val flip = if (clip["flipX"] == true) -1f else 1f
    private val frames = (clip["keyframes"] as? List<*>)?.map { it as Map<*, *> } ?: emptyList()
    private fun number(frame: Map<*, *>, key: String, fallback: Float = 0f): Float =
        (frame[key] as? Number)?.toFloat() ?: fallback
    private fun timestamp(frame: Map<*, *>): Double = (frame["sourceMs"] as Number).toDouble()
    override fun getGlMatrixArray(presentationTimeUs: Long): FloatArray {
        val source = sourceStartMs + presentationTimeUs / 1000.0 * speed
        var left: Map<*, *> = emptyMap<Any, Any>()
        var right = left
        var t = 0f
        if (frames.isNotEmpty()) {
            left = frames.first(); right = left
            if (source >= timestamp(frames.last())) { left = frames.last(); right = left }
            else if (source > timestamp(frames.first())) {
                for (i in 1 until frames.size) {
                    if (source <= timestamp(frames[i])) {
                        left = frames[i - 1]; right = frames[i]
                        t = ((source - timestamp(left)) / (timestamp(right) - timestamp(left))).toFloat()
                        break
                    }
                }
            }
        }
        fun blend(key: String, fallback: Float = 0f): Float = number(left, key, fallback) +
            (number(right, key, fallback) - number(left, key, fallback)) * t
        val zoom = blend("zoom", 1f)
        val radians = Math.toRadians(blend("rotation").toDouble())
        val c = cos(radians).toFloat() * zoom
        val s = sin(radians).toFloat() * zoom
        // NDC uses y-up; pan uses canvas fractions and rotation is clockwise.
        return floatArrayOf(
            c * flip, -s * width / height * flip, 0f, 0f,
            s * height / width, c, 0f, 0f,
            0f, 0f, 1f, 0f,
            blend("x") * 2, -blend("y") * 2, 0f, 1f
        )
    }
}

@UnstableApi
private class GainProcessor(private val volume: Float, private val segmentStartMs: Long = 0,
    private val musicStartMs: Long = 0, private val musicEndMs: Long = Long.MAX_VALUE,
    private val fadeInMs: Long = 0, private val fadeOutMs: Long = 0) : BaseAudioProcessor() {
    private var sampleRate = 0
    private var channels = 0
    private var encoding = C.ENCODING_PCM_16BIT
    private var frameIndex = 0L
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT && inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        sampleRate = inputAudioFormat.sampleRate; channels = inputAudioFormat.channelCount
        encoding = inputAudioFormat.encoding
        return inputAudioFormat
    }
    override fun onFlush() { frameIndex = 0 }
    override fun queueInput(inputBuffer: ByteBuffer) {
        val output = replaceOutputBuffer(inputBuffer.remaining())
        val bytesPerSample = if (encoding == C.ENCODING_PCM_FLOAT) 4 else 2
        while (inputBuffer.remaining() >= bytesPerSample * channels) {
            val timeMs = segmentStartMs + frameIndex * 1000.0 / sampleRate
            var envelope = 1.0
            if (fadeInMs > 0) envelope = min(envelope, (timeMs - musicStartMs) / fadeInMs)
            if (fadeOutMs > 0) envelope = min(envelope, (musicEndMs - timeMs) / fadeOutMs)
            val gain = volume * envelope.coerceIn(0.0, 1.0)
            repeat(channels) {
                if (encoding == C.ENCODING_PCM_FLOAT) output.putFloat((inputBuffer.float * gain).toFloat().coerceIn(-1f, 1f))
                else output.putShort((inputBuffer.short * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort())
            }
            frameIndex++
        }
        output.flip()
    }
}
