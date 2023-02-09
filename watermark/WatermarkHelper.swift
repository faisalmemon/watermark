//
//  WatermarkHelper.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import Foundation
import AVKit

struct WatermarkHelper {
    
    enum WatermarkError: Error {
        case cannotLoadResources
        case cannotAddTrack
        case cannotLoadVideoTrack(Error?)
        case cannotCopyOriginalAudioVideo(Error?)
        case noVideoTrackPresent
        case exportSessionCannotBeCreated
    }
    
    func addWatermark(inputVideo: AVAsset, outputURL: URL, watermark: UIImage, handler:@escaping (_ exportSession: AVAssetExportSession?)-> Void) {
        let mixComposition = AVMutableComposition()
        let asset = inputVideo
        let videoTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
        let timerange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
        
        let compositionVideoTrack:AVMutableCompositionTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))!
        
        do {
            try compositionVideoTrack.insertTimeRange(timerange, of: videoTrack, at: CMTime.zero)
            compositionVideoTrack.preferredTransform = videoTrack.preferredTransform
        } catch {
            print(error)
        }
        
        let watermarkFilter = CIFilter(name: "CISourceOverCompositing")!
        let watermarkImage = CIImage(image: watermark)
        let videoComposition = AVVideoComposition(asset: asset) { (filteringRequest) in
            let source = filteringRequest.sourceImage.clampedToExtent()
            watermarkFilter.setValue(source, forKey: "inputBackgroundImage")
            let transform = CGAffineTransform(translationX: filteringRequest.sourceImage.extent.width - (watermarkImage?.extent.width)! - 2, y: 0)
            watermarkFilter.setValue(watermarkImage?.transformed(by: transform), forKey: "inputImage")
            filteringRequest.finish(with: watermarkFilter.outputImage!, context: nil)
        }
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480) else {
            handler(nil)
            
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously { () -> Void in
            handler(exportSession)
        }
    }
    
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
        let width = videoSize.width
        let height = width / aspect
        imageLayer.frame = CGRect(
            x: 0,
            y: -height * 0.15,
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

        return try await withCheckedThrowingContinuation({
            (continuation: CheckedContinuation<AVAssetExportSession.Status, Error>) in
            session.exportAsynchronously {
                DispatchQueue.main.async {
                    if let error = session.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: session.status)
                    }
                }
            }
        })
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
    
    func exportIt() async throws -> TimeInterval {
        let timeStart = Date()
        guard
            let filePath = Bundle.main.path(forResource: "donut-spinning", ofType: "mp4"),
            let docUrl = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            let watermarkImage = UIImage(systemName: "seal") else {
            throw WatermarkError.cannotLoadResources
        }
        let videoAsset = AVAsset(url: URL(filePath: filePath))
        
        let outputURL = docUrl.appending(component: "watermark-donut-spinning.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        print(outputURL)
        let result = try await addWatermarkTopDriver(inputVideo: videoAsset, outputURL: outputURL, watermark: watermarkImage)
        let timeEnd = Date()
        let duration = timeEnd.timeIntervalSince(timeStart)
        print(result)
        return duration
    }
}
