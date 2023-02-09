//
//  WatermarkHelper.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import Foundation
import AVKit

enum TextAttributes {
    case semitransparent
}

struct Watermark {
    let text: String?
    let image: UIImage
    let type: TextAttributes
    func calculateImageFrame(parentSize: CGSize) -> CGRect {
        let interiorX = parentSize.width / 4.0
        let interiorY = parentSize.height / 4.0
        let sideLength = parentSize.width / 40.0
        let result = CGRect(x: interiorX, y: interiorY, width: sideLength, height: sideLength)
        return result
    }
    static func textAttributes(type: TextAttributes) -> TextAttributes {
        return type
    }
}

struct VideoInfo {
    var isPortrait: Bool {
        get {
            return true
        }
    }
}

/// Stack Overflow Question
/// `https://stackoverflow.com/questions/75312257/swift-add-watermark-to-a-video-is-very-slow`
struct WatermarkHelperOld {
    public func addWatermark(
        fromVideoAt videoURL: URL,
        watermark: Watermark,
        fileName: String,
        onSuccess: @escaping (URL) -> Void,
        onFailure: @escaping ((Error?) -> Void)
    ) {
        let asset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()

        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let assetTrack = asset.tracks(withMediaType: .video).first
        else {
            onFailure(nil)
            return
        }

        do {
            let timeRange = CMTimeRange(start: .zero, duration: assetTrack.timeRange.duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)

            if let audioAssetTrack = asset.tracks(withMediaType: .audio).first,
               let compositionAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioAssetTrack,
                    at: .zero
                )
            }
        } catch {
            onFailure(error)
            return
        }

        compositionTrack.preferredTransform = assetTrack.preferredTransform
        let videoInfo = orientation(from: assetTrack.preferredTransform)

        let videoSize: CGSize
        if videoInfo.isPortrait {
            videoSize = CGSize(
                width: assetTrack.naturalSize.height,
                height: assetTrack.naturalSize.width
            )
        } else {
            videoSize = assetTrack.naturalSize
        }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: videoSize)

        videoLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)

        let imageFrame = watermark.calculateImageFrame(parentSize: videoSize)
        addImage(watermark.image, to: overlayLayer, frame: imageFrame)
        let textOrigin = CGPoint(x: imageFrame.minX + 4, y: imageFrame.minY)
        if let text = watermark.text {
            addText(
                text,
                to: overlayLayer,
                origin: textOrigin,
                textAttributes: Watermark.textAttributes(type: watermark.type)
            )
        }

        let outputLayer = CALayer()
        outputLayer.frame = CGRect(origin: .zero, size: videoSize)
        outputLayer.addSublayer(videoLayer)
        outputLayer.addSublayer(overlayLayer)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = videoSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: outputLayer
        )
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = "sRGB"
        videoComposition.colorYCbCrMatrix = nil

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        videoComposition.instructions = [instruction]
        
        let layerInstruction = compositionLayerInstruction(
            for: compositionTrack,
            assetTrack: assetTrack
        )
        instruction.layerInstructions = [layerInstruction]

        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        )
        else {
            onFailure(nil)
            return
        }

        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(fileName)
            .appendingPathExtension("mov")

        export.videoComposition = videoComposition
        export.outputFileType = .mov
        export.outputURL = exportURL

        export.exportAsynchronously {
            DispatchQueue.main.async {
                switch export.status {
                case .completed:
                    onSuccess(exportURL)
                default:
                    onFailure(export.error)
                }
            }
        }
    }
    
    func orientation(from: CGAffineTransform) -> VideoInfo {
        return VideoInfo()
    }
    
    func compositionLayerInstruction(
        for compositionTrack: AVMutableCompositionTrack,
        assetTrack: AVAssetTrack) -> AVVideoCompositionLayerInstruction {
        return AVVideoCompositionLayerInstruction()
    }
    
    func addImage(_ image: UIImage, to overlayLayer: CALayer, frame: CGRect) {
        
    }
    
    func addText(
        _ text: String,
        to overlayLayer: CALayer,
        origin: CGPoint,
        textAttributes: TextAttributes
    ) {
        
    }
}
