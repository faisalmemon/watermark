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
        case cannotAddTrack
        case cannotLoadVideoTrack(Error?)
        case cannotCopyOriginalAudioVideo(Error?)
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
    
    func compositionAddVideoTrack(_ composition: AVMutableComposition) throws -> AVMutableCompositionTrack  {
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WatermarkError.cannotAddTrack
        }
        return compositionTrack
    }
    
    func loadVideoTrack(inputVideo: AVAsset) async throws -> AVAssetTrack {
        return try await withCheckedThrowingContinuation({
            (continuation: CheckedContinuation<AVAssetTrack, Error>) in
            
            inputVideo.loadTracks(withMediaType: .video) { tracks, error in
                if let tracks = tracks, let firstTrack = tracks.first {
                    continuation.resume(returning: firstTrack)
                } else {
                    continuation.resume(throwing: WatermarkError.cannotLoadVideoTrack(error))
                }
            }
        })
    }
    
    func bringOverVideoAndAudio(inputVideo: AVAsset, assetTrack: AVAssetTrack, compositionTrack: AVMutableCompositionTrack, composition: AVMutableComposition) async throws {
        do {
            // 1
            let timeRange = await CMTimeRange(start: .zero, duration: try inputVideo.load(.duration))
            // 2
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
            
            // 3
            if let audioAssetTrack = inputVideo.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioAssetTrack,
                    at: .zero)
            }
        } catch {
            // 4
            print(error)
            throw WatermarkError.cannotCopyOriginalAudioVideo(error)
        }
    }
    
    func addWatermarkTopDriver(inputVideo: AVAsset, outputURL: URL, watermark: UIImage) async throws -> AVAssetTrack? {
        let composition = AVMutableComposition()
        let compositionTrack = try compositionAddVideoTrack(composition)
        let videoAssetTrack = try await loadVideoTrack(inputVideo: inputVideo)
        return nil
    }
    
    
//    func addWatermark2(inputVideo: AVAsset,
//                       outputURL: URL,
//                       watermark: UIImage, handler: @escaping (_ exportSession: AVAssetExportSession?)-> Void) {
//
//        let composition = AVMutableComposition()
//        guard
//            let compositionTrack = composition.addMutableTrack(
//                withMediaType: .video,
//                preferredTrackID: kCMPersistentTrackID_Invalid)
//        else {
//            print("Something is wrong with the asset.")
//            handler(nil)
//            return
//        }
//        let assetTrack: AVAssetTrack
//        let assetTrack2 = inputVideo.loadTracks(withMediaType: .video, completionHandler: { tracks, error in
//
//            assetTrack = tracks.first
//        })
//    }

    
    func exportIt() {
        let bundle = Bundle.main
        guard
            let filePath = Bundle.main.path(forResource: "donut-spinning", ofType: "mp4"),
            let docUrl = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            let watermarkImage = UIImage(systemName: "seal") else {
            return
        }
        let videoAsset = AVAsset(url: URL(filePath: filePath))
    
        let outputURL = docUrl.appending(component: "watermark-donut-spinning.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        print(outputURL)
        addWatermark(inputVideo: videoAsset, outputURL: outputURL, watermark: watermarkImage, handler: { (exportSession) in
            guard let session = exportSession else {
                // Error
                return
            }
            switch session.status {
            case .completed:
                guard NSData(contentsOf: outputURL) != nil else {
                    // Error
                    return
                }
                
                // Now you can find the video with the watermark in the location outputURL
                
            default:
                // Error
                if let error = session.error {
                    print(error)
                }
                return
            }
        })
    }
}
