import AVFoundation
import CoreImage
import CoreVideo
import Flutter
import UIKit

/// AVFoundation composes retimed clips and audio; Core Image renders filters/text.
final class VideoEngine: NSObject, FlutterStreamHandler {
    private let channel: FlutterMethodChannel
    private let events: FlutterEventChannel
    private var sink: FlutterEventSink?
    private var exporter: AVAssetExportSession?
    private var pending: FlutterResult?
    private var timer: Timer?
    private var outputURL: URL?
    private var generation = 0

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "dev.frameforge/video", binaryMessenger: messenger)
        events = FlutterEventChannel(name: "dev.frameforge/export", binaryMessenger: messenger)
        super.init()
        events.setStreamHandler(self)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "inspect": self.inspect(call.arguments, result: result)
            case "inspectAudio": self.inspectAudio(call.arguments, result: result)
            case "export": self.startExport(call.arguments, result: result)
            case "cancelExport": self.cancel(); result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
    }

    private func inspectAudio(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any], let path = args["path"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing audio path", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard asset.tracks(withMediaType: .audio).first != nil,
                  asset.duration.seconds.isFinite, asset.duration.seconds >= 0.1 else {
                DispatchQueue.main.async { result(FlutterError(code: "inspect_audio_failed",
                    message: "The file contains no readable audio", details: nil)) }
                return
            }
            let duration = Int(asset.duration.seconds * 1000)
            DispatchQueue.main.async { result(["durationMs": duration]) }
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

    private func inspect(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any], let path = args["path"] as? String,
              let thumbnailPath = args["thumbnailPath"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing media paths", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = asset.tracks(withMediaType: .video).first,
                  asset.duration.seconds.isFinite, asset.duration.seconds >= 0.1 else {
                DispatchQueue.main.async { result(FlutterError(code: "inspect_failed", message: "The file contains no playable video", details: nil)) }
                return
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 360)
            var savedThumbnail: String?
            if let image = try? generator.copyCGImage(at: .zero, actualTime: nil),
               let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) {
                do { try data.write(to: URL(fileURLWithPath: thumbnailPath), options: .atomic); savedThumbnail = thumbnailPath }
                catch { /* Preview is optional; preserve a valid imported video. */ }
            }
            let size = track.naturalSize.applying(track.preferredTransform)
            let value: [String: Any] = ["durationMs": Int(asset.duration.seconds * 1000),
                "width": Int(abs(size.width)), "height": Int(abs(size.height)),
                "thumbnailPath": savedThumbnail as Any? ?? NSNull()]
            DispatchQueue.main.async { result(value) }
        }
    }

    private func startExport(_ arguments: Any?, result: @escaping FlutterResult) {
        guard pending == nil else { result(FlutterError(code: "busy", message: "An export is already running", details: nil)); return }
        guard let args = arguments as? [String: Any], let path = args["outputPath"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing export arguments", details: nil)); return
        }
        guard !FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "export_failed", message: "Output already exists", details: nil)); return
        }
        generation += 1
        let token = generation
        pending = result
        outputURL = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let built = try self.compose(args)
                DispatchQueue.main.async {
                    guard token == self.generation, self.pending != nil else { return }
                    // Render the SDR composition with the highest quality MP4 preset.
                    let preset = AVAssetExportPresetHighestQuality
                    guard let session = AVAssetExportSession(asset: built.composition, presetName: preset) else {
                        self.fail("This device cannot create the requested video"); return
                    }
                    session.outputURL = self.outputURL
                    session.outputFileType = .mp4
                    session.videoComposition = built.video
                    session.audioMix = built.audio
                    session.shouldOptimizeForNetworkUse = true
                    session.timeRange = CMTimeRange(start: .zero, duration: built.composition.duration)
                    self.exporter = session
                    self.timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                        self?.sink?(Double(session.progress))
                    }
                    session.exportAsynchronously { [weak self] in
                        DispatchQueue.main.async {
                            guard let self = self, token == self.generation, self.pending != nil else { return }
                            if session.status == .completed {
                                let savedPath = self.outputURL?.path
                                self.sink?(1.0)
                                let callback = self.clear()
                                callback?(savedPath)
                            } else { self.fail(session.error?.localizedDescription ?? "Video export failed") }
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if token == self.generation { self.fail(error.localizedDescription) }
                }
            }
        }
    }

    private struct Built {
        let composition: AVMutableComposition
        let video: AVMutableVideoComposition
        let audio: AVMutableAudioMix
    }
    private func time(_ milliseconds: Int) -> CMTime { CMTime(value: Int64(milliseconds), timescale: 1000) }
    private func error(_ message: String) -> NSError { NSError(domain: "FrameForge", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]) }

    private func compose(_ args: [String: Any]) throws -> Built {
        guard let clips = args["clips"] as? [[String: Any]], !clips.isEmpty,
              let width = args["width"] as? Int, let height = args["height"] as? Int,
              width > 0, height > 0, width <= 3840, height <= 3840,
              width % 2 == 0, height % 2 == 0 else { throw error("Invalid video settings") }
        let composition = AVMutableComposition()
        let fps = args["fps"] as? Int ?? 30
        guard [24, 30, 60].contains(fps) else { throw error("Unsupported frame rate") }
        let images = args["images"] as? [[String: Any]] ?? []
        guard images.count <= 20 else { throw error("Use up to 20 image overlays") }
        for image in images {
            guard let path = image["path"] as? String, FileManager.default.fileExists(atPath: path) else {
                throw error("An overlay image is missing")
            }
        }
        guard let footage = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw error("Could not allocate media tracks")
        }
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let sourceParameters = AVMutableAudioMixInputParameters(track: sourceAudio)
        sourceParameters.audioTimePitchAlgorithm = .spectral
        var instructions = [FrameInstruction]()
        var cursor = CMTime.zero
        for (index, clip) in clips.enumerated() {
            guard let path = clip["path"] as? String, let startMs = clip["startMs"] as? Int,
                  let endMs = clip["endMs"] as? Int, startMs >= 0, endMs - startMs >= 100 else {
                throw error("Invalid clip timing")
            }
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = asset.tracks(withMediaType: .video).first else { throw error("A source video is missing or unreadable") }
            let speed = (clip["renderSpeed"] as? NSNumber)?.doubleValue ?? (clip["speed"] as? NSNumber)?.doubleValue ?? 1
            guard speed.isFinite, speed > 0, speed <= 4.1 else { throw error("Invalid clip speed") }
            let outputMs = clip["outputDurationMs"] as? Int ?? Int((Double(endMs - startMs) / speed).rounded())
            guard outputMs > 0 else { throw error("Invalid clip duration") }
            let duration = time(outputMs)
            let clipVolume = (clip["volume"] as? NSNumber)?.floatValue ?? 1
            guard clipVolume.isFinite, clipVolume >= 0, clipVolume <= 1 else { throw error("Invalid clip volume") }
            sourceParameters.setVolume(clip["muted"] as? Bool == true ? 0 : clipVolume, at: cursor)
            let rawDuration = time(endMs - startMs)
            let destinationRange = CMTimeRange(start: cursor, duration: rawDuration)
            let range = CMTimeRange(start: time(startMs), duration: rawDuration)
            try footage.insertTimeRange(range, of: track, at: cursor)
            // Allocate the complete unscaled audio segment, including silent gaps.
            sourceAudio.insertEmptyTimeRange(destinationRange)
            if clip["muted"] as? Bool != true, let audio = asset.tracks(withMediaType: .audio).first {
                // Some video files have a shorter audio track. Fill the remainder with silence.
                let audioEnd = CMTimeMinimum(time(endMs), CMTimeRangeGetEnd(audio.timeRange))
                let audioStart = CMTimeMaximum(time(startMs), audio.timeRange.start)
                if audioEnd > audioStart {
                    let destination = cursor + (audioStart - time(startMs))
                    sourceAudio.removeTimeRange(CMTimeRange(start: destination, duration: audioEnd - audioStart))
                    try sourceAudio.insertTimeRange(CMTimeRange(start: audioStart, end: audioEnd), of: audio, at: destination)
                }
            }
            if rawDuration != duration {
                footage.scaleTimeRange(destinationRange, toDuration: duration)
                sourceAudio.scaleTimeRange(destinationRange, toDuration: duration)
            }
            let oriented = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
            let sx = size.width / abs(oriented.width), sy = size.height / abs(oriented.height)
            let scale = clip["fit"] as? String == "fill" ? max(sx, sy) : min(sx, sy)
            let transform = track.preferredTransform
                .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: (size.width - abs(oriented.width) * scale) / 2,
                                                 y: (size.height - abs(oriented.height) * scale) / 2))
            let matrix = (clip["filterMatrix"] as? [NSNumber])?.map { $0.doubleValue } ?? FrameInstruction.identityMatrix
            guard matrix.count == 20, matrix.allSatisfy({ $0.isFinite }) else { throw error("Invalid filter matrix") }
            let instruction = FrameInstruction(timeRange: CMTimeRange(start: cursor, duration: duration),
                trackID: footage.trackID, transform: transform, matrix: matrix,
                fadeIn: index > 0 && clips[index - 1]["transition"] as? String == "fade",
                fadeOut: index < clips.count - 1 && clip["transition"] as? String == "fade",
                texts: args["texts"] as? [[String: Any]] ?? [], images: images,
                sourceStartMs: startMs, speed: speed, flipX: clip["flipX"] as? Bool ?? false,
                keyframes: (clip["keyframes"] as? [[String: Any]] ?? []).map { MotionPoint($0) })
            instructions.append(instruction)
            cursor = cursor + duration
        }
        let video = AVMutableVideoComposition()
        video.renderSize = size
        video.frameDuration = CMTime(value: 1, timescale: Int32(fps))
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        video.instructions = instructions
        video.customVideoCompositorClass = FrameCompositor.self
        let mix = AVMutableAudioMix()
        var audioParameters = [AVMutableAudioMixInputParameters]()
        audioParameters.append(sourceParameters)
        let audioTracks: [[String: Any]]
        if let tracks = args["audioTracks"] as? [[String: Any]] { audioTracks = tracks }
        else if let music = args["music"] as? [String: Any] { audioTracks = [music] }
        else { audioTracks = [] }
        guard audioTracks.count <= 8,
              audioTracks.reduce(0, { $0 + (($1["segments"] as? [[String: Any]])?.count ?? 0) }) <= 4000 else {
            throw error("Use up to eight audio tracks and choose longer looping sections")
        }
        for music in audioTracks {
            guard let path = music["path"] as? String,
                  let segments = music["segments"] as? [[String: Any]] else { throw error("Invalid audio track") }
            if segments.isEmpty { continue }
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = asset.tracks(withMediaType: .audio).first,
                  track.timeRange.duration.seconds.isFinite, track.timeRange.duration.seconds > 0,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw error("An audio file is missing or unreadable")
            }
            guard segments.count <= 2000 else { throw error("Choose a longer music section or turn off looping") }
            for segment in segments {
                guard let start = segment["sourceStartMs"] as? Int, let end = segment["sourceEndMs"] as? Int,
                      let target = segment["timelineStartMs"] as? Int,
                      let targetEnd = segment["timelineEndMs"] as? Int, start >= 0, end > start,
                      target >= 0, targetEnd - target == end - start else { throw error("Invalid music timing") }
                let requested = CMTimeRange(start: time(start), duration: time(end - start))
                let available = CMTimeRangeGetIntersection(requested, track.timeRange)
                if available.duration > .zero {
                    try destination.insertTimeRange(available, of: track,
                        at: time(target) + (available.start - requested.start))
                }
            }
            let parameters = AVMutableAudioMixInputParameters(track: destination)
            let volume = (music["volume"] as? NSNumber)?.floatValue ?? 0.6
            guard volume.isFinite, volume >= 0, volume <= 1 else { throw error("Invalid audio volume") }
            let start = time(music["renderStartMs"] as? Int ?? 0)
            let end = time(music["renderEndMs"] as? Int ?? 0)
            let fadeIn = time(music["renderFadeInMs"] as? Int ?? 0)
            let fadeOut = time(music["renderFadeOutMs"] as? Int ?? 0)
            parameters.setVolume(fadeIn > .zero ? 0 : volume, at: start)
            if fadeIn > .zero {
                parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                    timeRange: CMTimeRange(start: start, duration: fadeIn))
            }
            if fadeOut > .zero {
                parameters.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                    timeRange: CMTimeRange(start: end - fadeOut, duration: fadeOut))
            }
            audioParameters.append(parameters)
        }
        mix.inputParameters = audioParameters
        return Built(composition: composition, video: video, audio: mix)
    }

    private func clear() -> FlutterResult? {
        timer?.invalidate(); timer = nil
        let callback = pending
        pending = nil; exporter = nil; outputURL = nil
        return callback
    }
    private func fail(_ message: String) {
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
        clear()?(FlutterError(code: "export_failed", message: message, details: nil))
    }
    private func cancel() {
        generation += 1
        exporter?.cancelExport()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
        clear()?(FlutterError(code: "export_cancelled", message: "Export cancelled", details: nil))
    }
    deinit { timer?.invalidate(); exporter?.cancelExport() }
}

private struct MotionPoint {
    var sourceMs: Double = 0
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    var rotation: Double = 0
    init(_ json: [String: Any] = [:]) {
        sourceMs = (json["sourceMs"] as? NSNumber)?.doubleValue ?? 0
        zoom = (json["zoom"] as? NSNumber)?.doubleValue ?? 1
        x = (json["x"] as? NSNumber)?.doubleValue ?? 0
        y = (json["y"] as? NSNumber)?.doubleValue ?? 0
        rotation = (json["rotation"] as? NSNumber)?.doubleValue ?? 0
    }
    func blended(to other: MotionPoint, fraction: Double) -> MotionPoint {
        var result = self
        result.zoom += (other.zoom - zoom) * fraction
        result.x += (other.x - x) * fraction; result.y += (other.y - y) * fraction
        result.rotation += (other.rotation - rotation) * fraction
        return result
    }
}

private final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    static let identityMatrix: [Double] = [
        1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
        0, 0, 1, 0, 0, 0, 0, 0, 1, 0
    ]
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let transform: CGAffineTransform
    let matrix: [Double]
    let fadeIn: Bool
    let fadeOut: Bool
    let texts: [[String: Any]]
    let images: [[String: Any]]
    let sourceStartMs: Int
    let speed: Double
    let flipX: Bool
    let keyframes: [MotionPoint]

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, transform: CGAffineTransform,
         matrix: [Double], fadeIn: Bool, fadeOut: Bool, texts: [[String: Any]],
         images: [[String: Any]], sourceStartMs: Int, speed: Double, flipX: Bool, keyframes: [MotionPoint]) {
        self.timeRange = timeRange; self.trackID = trackID; self.transform = transform
        self.matrix = matrix; self.fadeIn = fadeIn; self.fadeOut = fadeOut; self.texts = texts
        self.images = images; self.sourceStartMs = sourceStartMs; self.speed = speed
        self.flipX = flipX; self.keyframes = keyframes
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        super.init()
    }

    func motionTransform(at timestamp: CMTime, size: CGSize) -> CGAffineTransform {
        let source = Double(sourceStartMs) + (timestamp - timeRange.start).seconds * 1000 * speed
        var point = MotionPoint()
        if let first = keyframes.first, let last = keyframes.last {
            point = first
            if source >= last.sourceMs { point = last }
            else if source > first.sourceMs {
                for i in 1..<keyframes.count where source <= keyframes[i].sourceMs {
                    let left = keyframes[i - 1], right = keyframes[i]
                    point = left.blended(to: right, fraction: (source - left.sourceMs) / (right.sourceMs - left.sourceMs))
                    break
                }
            }
        }
        let angle = point.rotation * .pi / 180
        let c = CGFloat(cos(angle) * point.zoom), s = CGFloat(sin(angle) * point.zoom)
        let flip: CGFloat = flipX ? -1 : 1
        let cx = size.width / 2, cy = size.height / 2
        return CGAffineTransform(a: c * flip, b: s * flip, c: -s, d: c,
            tx: cx + CGFloat(point.x) * size.width - c * flip * cx + s * cy,
            ty: cy + CGFloat(point.y) * size.height - s * flip * cx - c * cy)
    }

    func brightness(at timestamp: CMTime) -> CGFloat {
        let local = (timestamp - timeRange.start).seconds
        let duration = timeRange.duration.seconds
        let fade = min(0.3, duration / 2)
        var result = 1.0
        if fadeIn { result = min(result, local / fade) }
        if fadeOut { result = min(result, (duration - local) / fade) }
        return CGFloat(max(0, min(1, result)))
    }
}

/// A single renderer applies footage filters and fades before overlaying text.
/// Text uses output time, so speed changes never retime the soundtrack or text.
private final class FrameCompositor: NSObject, AVVideoCompositing {
    private let queue = DispatchQueue(label: "dev.frameforge.frames", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let lock = NSLock()
    private var generation = 0
    private var textKey: String?
    private var textImage: CIImage?
    private var assets = [String: UIImage]()

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA]]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Each request carries its own render context, including its output size.
    }

    private func currentGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }; return generation
    }

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock(); generation += 1; lock.unlock()
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        let token = currentGeneration()
        queue.async { [self] in
            autoreleasepool {
                guard token == currentGeneration() else { request.finishCancelledRequest(); return }
                guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
                      let source = request.sourceFrame(byTrackID: instruction.trackID),
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "FrameForge", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not render a video frame"]))
                    return
                }
                let bounds = CGRect(origin: .zero, size: request.renderContext.size)
                var image = CIImage(cvPixelBuffer: source)
                image = applyMatrix(instruction.matrix, to: image)
                // Convert the track's top-left transform into Core Image coordinates.
                let sourceFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: image.extent.height)
                let outputFlip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
                image = image.transformed(by: sourceFlip.concatenating(instruction.transform).concatenating(outputFlip))
                // Crop the fitted frame before moving it, matching preview/Media3.
                image = image.cropped(to: bounds).transformed(by: outputFlip
                    .concatenating(instruction.motionTransform(at: request.compositionTime, size: bounds.size))
                    .concatenating(outputFlip))
                let level = instruction.brightness(at: request.compositionTime)
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: level, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: level, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: level, w: 0),
                ])
                image = image.composited(over: CIImage(color: .black).cropped(to: bounds)).cropped(to: bounds)
                do {
                    if let scene = try overlay(instruction.texts, images: instruction.images,
                        at: request.compositionTime, size: bounds.size) { image = scene.composited(over: image) }
                } catch { request.finish(with: error); return }
                context.render(image, to: output, bounds: bounds, colorSpace: colorSpace)
                guard token == currentGeneration() else { request.finishCancelledRequest(); return }
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    private func applyMatrix(_ matrix: [Double], to image: CIImage) -> CIImage {
        func row(_ offset: Int) -> CIVector {
            CIVector(x: CGFloat(matrix[offset]), y: CGFloat(matrix[offset + 1]),
                z: CGFloat(matrix[offset + 2]), w: CGFloat(matrix[offset + 3]))
        }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": row(0), "inputGVector": row(5), "inputBVector": row(10), "inputAVector": row(15),
            "inputBiasVector": CIVector(x: CGFloat(matrix[4] / 255), y: CGFloat(matrix[9] / 255),
                z: CGFloat(matrix[14] / 255), w: CGFloat(matrix[19] / 255)),
        ])
    }

    private func overlay(_ texts: [[String: Any]], images: [[String: Any]], at timestamp: CMTime, size: CGSize) throws -> CIImage? {
        let timeMs = timestamp.seconds * 1000
        let active = texts.filter { text in
            guard let start = text["startMs"] as? Int, let end = text["endMs"] as? Int else { return false }
            return timeMs >= Double(start) && timeMs < Double(end)
        }
        let activeImages = images.filter { image in
            guard let start = image["startMs"] as? Int, let end = image["endMs"] as? Int else { return false }
            return timeMs >= Double(start) && timeMs < Double(end)
        }
        for image in activeImages {
            guard let path = image["path"] as? String else { continue }
            if assets[path] == nil {
                guard let asset = UIImage(contentsOfFile: path) else {
                    throw NSError(domain: "FrameForge", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "An overlay image is unreadable"])
                }
                assets[path] = asset
            }
        }
        let key = "\(size.width)x\(size.height):" + active.map { $0["id"] as? String ?? "" }.joined(separator: ",") +
            ":" + activeImages.map { $0["id"] as? String ?? "" }.joined(separator: ",")
        if key == textKey { return textImage }
        textKey = key; textImage = nil
        guard !active.isEmpty || !activeImages.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false; format.preferredRange = .standard
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for image in activeImages {
                guard let path = image["path"] as? String, let asset = assets[path],
                      let graphics = UIGraphicsGetCurrentContext() else { continue }
                let imageWidth = size.width * CGFloat((image["width"] as? NSNumber)?.doubleValue ?? 0.35)
                let aspect = CGFloat((image["aspect"] as? NSNumber)?.doubleValue ?? 1)
                let imageHeight = imageWidth / aspect
                graphics.saveGState()
                graphics.translateBy(x: size.width * CGFloat((image["x"] as? NSNumber)?.doubleValue ?? 0.5),
                    y: size.height * CGFloat((image["y"] as? NSNumber)?.doubleValue ?? 0.5))
                graphics.rotate(by: CGFloat((image["rotation"] as? NSNumber)?.doubleValue ?? 0) * .pi / 180)
                asset.draw(in: CGRect(x: -imageWidth / 2, y: -imageHeight / 2, width: imageWidth, height: imageHeight),
                    blendMode: .normal, alpha: CGFloat((image["opacity"] as? NSNumber)?.doubleValue ?? 1))
                graphics.restoreGState()
            }
            for text in active {
                guard let value = text["text"] as? String else { continue }
                let fontSize = size.height * CGFloat((text["size"] as? NSNumber)?.doubleValue ?? 0.055)
                let y = size.height * CGFloat((text["y"] as? NSNumber)?.doubleValue ?? 0.78)
                let packed = (text["color"] as? NSNumber)?.uint32Value ?? 0xFFFFFFFF
                let color = UIColor(red: CGFloat((packed >> 16) & 255) / 255,
                    green: CGFloat((packed >> 8) & 255) / 255, blue: CGFloat(packed & 255) / 255,
                    alpha: CGFloat((packed >> 24) & 255) / 255)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center; paragraph.lineSpacing = fontSize * 0.15
                let shadow = NSShadow()
                shadow.shadowColor = UIColor.black; shadow.shadowBlurRadius = 2
                shadow.shadowOffset = CGSize(width: 0, height: 1)
                let attributed = NSAttributedString(string: value, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold), .foregroundColor: color,
                    .paragraphStyle: paragraph, .shadow: shadow,
                ])
                let width = size.width * 0.84
                let measured = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                let height = ceil(measured.height)
                attributed.draw(in: CGRect(x: size.width * 0.08, y: y - height / 2, width: width, height: height))
            }
        }
        if let image = rendered.cgImage { textImage = CIImage(cgImage: image) }
        return textImage
    }
}
