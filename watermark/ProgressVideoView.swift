//
//  ProgressVideoView.swift
//  watermark
//
//  Created by Faisal Memon on 14/02/2023.
//

import SwiftUI

struct ProgressVideoView: View {
    
    @Binding var progress: Double
    
    init(bindingProgress: Binding<Double>) {
        _progress = bindingProgress
    }
    
    var body: some View {
        VStack {
            Text("Processing Video...")
            ProgressView(value: progress)
        }
    }
}

struct ProcessVideoView_Previews: PreviewProvider {
    @State static var progress = 0.5
    static var previews: some View {
        ProgressVideoView(bindingProgress: $progress)
    }
}
