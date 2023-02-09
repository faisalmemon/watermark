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
   
    
    var body: some View {
        VStack {
            Text("Original Video")
            if duration != 0 {
                VideoPlayer(player: AVPlayer(url:  Bundle.main.url(forResource: "donut-spinning", withExtension: "mp4")!))
                    .frame(height: 70)
            } else {
                VideoPlayer(player: AVPlayer(url:  Bundle.main.url(forResource: "donut-spinning", withExtension: "mp4")!))
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
                        if let processingTime = try? await helper.exportIt() {
                            duration = processingTime
                        } else {
                            duration = 0.0
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
