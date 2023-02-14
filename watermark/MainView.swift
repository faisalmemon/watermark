//
//  ContentView.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import SwiftUI
import AVKit

struct MainView: View {
    
    @State var duration: TimeInterval = 0.0
    @State var progress = 0.0
    @State var showProgressScreen = false
    
    var body: some View {
        
        NavigationStack {
            VStack {
                Text("Original Video")
                if duration != 0 {
                    VideoPlayer(player: AVPlayer(url:  Bundle.main.url(forResource: "gazing", withExtension: "m4v")!))
                        .frame(height: 70)
                } else {
                    VideoPlayer(player: AVPlayer(url:  Bundle.main.url(forResource: "gazing", withExtension: "m4v")!))
                        .frame(height: 400)
                    Text("Watermark")
                    Image(systemName: "seal")
                        .frame(height: 20)
                }
                
                if duration != 0 {
                    Text("Watermarked Video")
                    Text("Created after \(duration) seconds")
                    
                    VideoPlayer(player: AVPlayer(url: try! Resource().outputURL))
                        .frame(height: 400)
                } else {
                    Button("Add Watermark") {
                        let helper = WatermarkHelper()
                        Task {
                            if let exporter = try? await helper.exporterForWatermarkedVideo(progress: $progress) {
                                showProgressScreen = true
                                _ = try? await exporter.export()
                                duration = exporter.duration ?? 0.0
                                showProgressScreen = false
                            }
                        }
                    }.navigationDestination(isPresented: $showProgressScreen) {
                        ProgressVideoView(bindingProgress: $progress)
                    }
                }
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
