//
//  ContentView.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import SwiftUI

struct ContentView: View {
    
    @State var duration: TimeInterval = 0.0
   
    
    var body: some View {
        VStack {
            if duration != 0 {
                Text("Duration \(duration)")
            }
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
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
