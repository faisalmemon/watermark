//
//  ContentView.swift
//  watermark
//
//  Created by Faisal Memon on 09/02/2023.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Add Watermark") {
                let helper = WatermarkHelper()
                Task {
                    try? await helper.exportIt()
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
