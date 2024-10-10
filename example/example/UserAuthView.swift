//
//  ContentView.swift
//  swift-example
//
//  Created by Brian Corbin on 4/19/24.
//

import SwiftUI
import CapsuleSwift

enum NavigationDestination {
    case verifyEmail, wallet
}

let defaultDevEnv = CapsuleEnvironment.dev(relyingPartyId: "optimum-seagull-discrete.ngrok-free.app", jsBridgeUrl: nil)
let defaultSandboxEnv = CapsuleEnvironment.sandbox(jsBridgeUrl: nil)
let defaultBetaEnv = CapsuleEnvironment.beta(jsBridgeUrl: nil)
let defaultProdEnv = CapsuleEnvironment.prod(jsBridgeUrl: nil)

struct UserAuthView: View {
    @EnvironmentObject var capsuleManager: CapsuleManager

    @State private var email = ""
    @State private var path = [NavigationDestination]()
    
    @State private var showWalletView = false
    @State private var selectedEnvironment = defaultDevEnv
    @State private var newApiKey: String = ""
    
    @State private var showingSetApiKeyAlert = false
    
    @Environment(\.authorizationController) private var authorizationController
        
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                CapsuleWebView(capsuleManager: capsuleManager).hidden()
                VStack {
                    HStack {
                        Text("Environment")
                        if #available(iOS 17.0, *) {
                            Picker("Environment", selection: $selectedEnvironment) {
                                Text("Dev").tag(defaultDevEnv)
                                Text("Sandbox").tag(defaultSandboxEnv)
                                Text("Beta").tag(defaultBetaEnv)
                                Text("Prod").tag(defaultProdEnv)
                            }.onChange(of: selectedEnvironment) { oldValue, newValue in
                                capsuleManager.environment = selectedEnvironment
                            }
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                    
                    Button("Set API Key") {
                        showingSetApiKeyAlert.toggle()
                    }
                    .buttonStyle(.bordered)
                    .alert("", isPresented: $showingSetApiKeyAlert) {
                        TextField("API Key", text: $newApiKey)
                        Button("Set API Key") {
                            capsuleManager.apiKey = newApiKey
                        }
                        Button("Cancel", role: .cancel) {
                            showingSetApiKeyAlert.toggle()
                        }
                    }
                    
                    Spacer()
                    
                    TextField("Email Address", text: $email)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                    HStack {
                        Button("Sign Up") {
                            Task.init {
                                print("checking if user exists...")
                                let userExists = try await capsuleManager.checkIfUserExists(email: email)
                                print(userExists)
                                if userExists {
                                    return
                                }
                                
                                try await capsuleManager.createUser(email: email)
                                path.append(.verifyEmail)
                            }
                        }
                        Button("Log In") {
                            Task.init {
                                try await capsuleManager.login(authorizationController: authorizationController)
                                path.append(.wallet)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
                .navigationDestination(for: NavigationDestination.self) { path in
                    switch path {
                    case .verifyEmail:
                        VerifyEmailView(email: email, path: $path)
                    case .wallet:
                        WalletView(wallet: capsuleManager.wallets.first, path: $path)
                    }
                }
            }
        }
    }
}

#Preview {
    UserAuthView()
}
