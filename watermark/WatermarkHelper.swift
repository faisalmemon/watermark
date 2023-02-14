//
//  WatermarkHelper.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import Foundation
import AVKit

enum WatermarkError: Error {
    case cannotLoadResources
    case cannotAddTrack
    case cannotLoadVideoTrack(Error?)
    case cannotCopyOriginalAudioVideo(Error?)
    case noVideoTrackPresent
    case exportSessionCannotBeCreated
}

struct Resource {
    let videoAsset: AVAsset
    let watermarkImage: UIImage
    let outputURL: URL
    
    init() throws {
        guard
            let filePath = Bundle.main.path(forResource: "donut-spinning", ofType: "mp4"),
            let docUrl = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            let image = UIImage(systemName: "seal") else {
            throw WatermarkError.cannotLoadResources
        }
        watermarkImage = image
        videoAsset = AVAsset(url: URL(filePath: filePath))
        outputURL = docUrl.appending(component: "watermark-donut-spinning.mp4")
    }
}

struct WatermarkHelper {
    
    func compositionAddMediaTrack(_ composition: AVMutableComposition, withMediaType mediaType: AVMediaType) throws -> AVMutableCompositionTrack  {
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: mediaType,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WatermarkError.cannotAddTrack
        }
        return compositionTrack
    }
    
    func loadTrack(inputVideo: AVAsset, withMediaType mediaType: AVMediaType) async throws -> AVAssetTrack? {
        return try await withCheckedThrowingContinuation({
            (continuation: CheckedContinuation<AVAssetTrack?, Error>) in
            
            inputVideo.loadTracks(withMediaType: mediaType) { tracks, error in
                if let tracks = tracks {
                    continuation.resume(returning: tracks.first)
                } else {
                    continuation.resume(throwing: WatermarkError.cannotLoadVideoTrack(error))
                }
            }
        })
    }
    
    func bringOverVideoAndAudio(inputVideo: AVAsset, assetTrack: AVAssetTrack, compositionTrack: AVMutableCompositionTrack, composition: AVMutableComposition) async throws {
        do {
            let timeRange = await CMTimeRange(start: .zero, duration: try inputVideo.load(.duration))
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
            if let audioAssetTrack = try await loadTrack(inputVideo: inputVideo, withMediaType: .audio) {
                let compositionAudioTrack = try compositionAddMediaTrack(composition, withMediaType: .audio)
                try compositionAudioTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
            }
        } catch {
            print(error)
            throw WatermarkError.cannotCopyOriginalAudioVideo(error)
        }
    }
    
    private func orientation(from transform: CGAffineTransform) -> (orientation: UIImage.Orientation, isPortrait: Bool) {
        var assetOrientation = UIImage.Orientation.up
        var isPortrait = false
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            assetOrientation = .right
            isPortrait = true
        } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            assetOrientation = .left
            isPortrait = true
        } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
            assetOrientation = .up
        } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            assetOrientation = .down
        }
        
        return (assetOrientation, isPortrait)
    }
    
    func preferredTransformAndSize(compositionTrack: AVMutableCompositionTrack, assetTrack: AVAssetTrack) async throws -> (preferredTransform: CGAffineTransform, videoSize: CGSize) {
        
        let transform = try await assetTrack.load(.preferredTransform)
        let videoInfo = orientation(from: transform)
        
        let videoSize: CGSize
        let naturalSize = try await assetTrack.load(.naturalSize)
        if videoInfo.isPortrait {
            videoSize = CGSize(
                width: naturalSize.height,
                height: naturalSize.width)
        } else {
            videoSize = naturalSize
        }
        return (transform, videoSize)
    }
    
    private func compositionLayerInstruction(for track: AVCompositionTrack, assetTrack: AVAssetTrack, preferredTransform: CGAffineTransform) -> AVMutableVideoCompositionLayerInstruction {
        
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        instruction.setTransform(preferredTransform, at: .zero)
        
        return instruction
    }
    
    private func addImage(to layer: CALayer, watermark: UIImage, videoSize: CGSize) {
        let imageLayer = CALayer()
        let aspect: CGFloat = watermark.size.width / watermark.size.height
        let width = videoSize.width / 4
        let height = width / aspect
        imageLayer.frame = CGRect(
            x: width,
            y: 0,
            width: width,
            height: height)
        imageLayer.contents = watermark.cgImage
        layer.addSublayer(imageLayer)
    }

    
    func composeVideo(composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, compositionTrack: AVMutableCompositionTrack, assetTrack: AVAssetTrack, preferredTransform: CGAffineTransform) {
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: composition.duration)
        videoComposition.instructions = [instruction]
        let layerInstruction = compositionLayerInstruction(
            for: compositionTrack,
            assetTrack: assetTrack, preferredTransform: preferredTransform)
        instruction.layerInstructions = [layerInstruction]
    }
    
    func exportSession(composition: AVMutableComposition, videoComposition: AVMutableVideoComposition, outputURL: URL) throws -> AVAssetExportSession {
        guard let export = AVAssetExportSession(
          asset: composition,
          presetName: AVAssetExportPresetHighestQuality)
          else {
            print("Cannot create export session.")
            throw WatermarkError.exportSessionCannotBeCreated
        }
        export.videoComposition = videoComposition
        export.outputFileType = .mp4
        export.outputURL = outputURL
        return export
    }
    
    func executeSession(_ session: AVAssetExportSession) async throws -> AVAssetExportSession.Status {

        await session.export()
                
        if let error = session.error {
            throw error
        } else {
            return session.status
        }
    }
    
    func addWatermarkTopDriver(inputVideo: AVAsset, outputURL: URL, watermark: UIImage) async throws -> AVAssetExportSession.Status {
        let composition = AVMutableComposition()
        let compositionTrack = try compositionAddMediaTrack(composition, withMediaType: .video)
        guard let videoAssetTrack = try await loadTrack(inputVideo: inputVideo, withMediaType: .video) else {
            throw WatermarkError.noVideoTrackPresent
        }
        try await bringOverVideoAndAudio(inputVideo: inputVideo, assetTrack: videoAssetTrack, compositionTrack: compositionTrack, composition: composition)
        let transformAndSize = try await preferredTransformAndSize(compositionTrack: compositionTrack, assetTrack: videoAssetTrack)
        compositionTrack.preferredTransform = transformAndSize.preferredTransform
        
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: transformAndSize.videoSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: transformAndSize.videoSize)
        addImage(to: overlayLayer, watermark: watermark, videoSize: transformAndSize.videoSize)

        let outputLayer = CALayer()
        outputLayer.frame = CGRect(origin: .zero, size: transformAndSize.videoSize)
        outputLayer.addSublayer(videoLayer)
        outputLayer.addSublayer(overlayLayer)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = transformAndSize.videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: outputLayer)
        composeVideo(composition: composition, videoComposition: videoComposition, compositionTrack: compositionTrack, assetTrack: videoAssetTrack, preferredTransform: transformAndSize.preferredTransform)
        
        let session = try exportSession(composition: composition, videoComposition: videoComposition, outputURL: outputURL)
        return try await executeSession(session)
    }
    
    /// Creates a watermarked movie and saves it to the documents directory.
    ///
    /// For an 8 second video (251 frames), this code takes 2.56 seconds on iPhone 11 producing a high quality video at 30 FPS.
    /// - Returns: Time interval taken for processing.
    public func exportIt() async throws -> TimeInterval {
        let timeStart = Date()
        let resources = try Resource()
        
        try? FileManager.default.removeItem(at: resources.outputURL)
        print(resources.outputURL)
        let result = try await addWatermarkTopDriver(inputVideo: resources.videoAsset, outputURL: resources.outputURL, watermark: resources.watermarkImage)
        let timeEnd = Date()
        let duration = timeEnd.timeIntervalSince(timeStart)
        print(result)
        return duration
    }
}
