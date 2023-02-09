//
//  WatermarkHelper.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import Foundation
import AVKit

struct WatermarkHelper {
    
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
