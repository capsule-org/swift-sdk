//
//  exampleApp.swift
//  example
//
//  Created by Brian Corbin on 6/18/24.
//

import SwiftUI
import CapsuleSwift
@main
struct exampleApp: App {
    @StateObject var capsuleManager = CapsuleManager(environment: defaultSandboxEnv, apiKey: "8ee2d015fbc6062a6e30bdc472f2946c")
    
    var body: some Scene {
        WindowGroup {
            UserAuthView()
                .environmentObject(capsuleManager)
        }
    }
}
