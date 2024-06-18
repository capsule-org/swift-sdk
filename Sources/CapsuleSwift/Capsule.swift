//
//  Capsule.swift
//  swift-example
//
//  Created by Brian Corbin on 4/23/24.
//

import SwiftUI
import WebKit
import AuthenticationServices
import os

/// A UIViewRepresentable that allows access to functions of the [JavaScript Bridge](https://github.com/capsule-org/web-sdk/blob/main/sites/bridge/src/index.ts)
///
/// > Important: This must be added to your view to enable the Capsule instance to access the
/// > [JavaScript Bridge](https://github.com/capsule-org/web-sdk/blob/main/sites/bridge/src/index.ts),
/// > and should be hidden
///
/// ```swift
/// ZStack {
///     CapsuleWebView(viewModel: capsule).hidden()
///     ...
/// ```
@available(iOS 16.4, *)
@MainActor
public struct CapsuleWebView: UIViewRepresentable {
    
    /// An instance of the Capsule class
    public var capsule: Capsule

    /**
     Initializes a new CapsuleWebView with the provided Capsule instance

     - Parameters:
        - capsule: An instance of the Capsule class

     - Returns: A new instance of the CapsuleWebView struct
     */
    public init(capsule: Capsule) {
        self.capsule = capsule
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: CGRect.zero)
        webView.configuration.userContentController.add(capsule, name: "callback")
        capsule.webView = webView
        capsule.loadJsBridge()
        return webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}

@available(iOS 16.4, *)
@MainActor
public class Capsule: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    public static let packageVersion = "0.0.2"
        
    enum CapsuleError: Error {
        case missingResponseData
        case bridgeError(String)
    }
    
    private var continuation: CheckedContinuation<Any?, Error>?
    private let passkeysManager: PasskeysManager

    @Published public var wallet: Wallet?
    public var environment: CapsuleEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    
    public var apiKey: String
    
    weak var webView: WKWebView? {
        didSet {
            webView?.navigationDelegate = self
        }
    }
    
    public init(environment: CapsuleEnvironment, apiKey: String) {
        self.environment = environment
        self.apiKey = apiKey
        self.passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let resp = message.body as! [String: Any]
        
        if let error = resp["error"] {
            continuation?.resume(throwing: CapsuleError.bridgeError(error as? String ?? "No further information provided"))
            return
        }
        
        continuation?.resume(returning: resp["responseData"])
    }
    
    public func loadJsBridge() {
        webView!.load(URLRequest(url: environment.jsBridgeUrl))
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initCapsule()
    }
    
    public func initCapsule() {
        webView!.evaluateJavaScript("""
      window.postMessage({
        messageType: 'Capsule#init',
        arguments: {
          environment: '\(environment.name)',
          apiKey: '\(apiKey)',
          platform: 'iOS',
          package: '\(Self.packageVersion)'
        }
      });
    """)
    }
    
    private func postMessage(method: String, arguments: [Encodable]) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView!.evaluateJavaScript("""
          window.postMessage({
            'messageType': 'Capsule#invokeMethod',
            'methodName': '\(method)',
            'arguments': \(arguments)
          });
        """)
        }
    }
}

@available(iOS 16.4, *)
extension Capsule {
    public func checkIfUserExists(email: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExists", arguments: [email])
        return result as! Bool
    }
    
    public func createUser(email: String) async throws {
        try await postMessage(method: "createUser", arguments: [email])
        return
    }
    
    public func login(authorizationController: AuthorizationController) async throws {
        let getWebChallengeResult = try await postMessage(method: "getWebChallenge", arguments: [])
        let challenge = (getWebChallengeResult as! [String: String])["challenge"]!
        let signIntoPasskeyAccountResult = try await passkeysManager.signIntoPasskeyAccount(authorizationController: authorizationController, challenge: challenge)
        
        let id = signIntoPasskeyAccountResult.credentialID.base64URLEncodedString()
        let authenticatorData = signIntoPasskeyAccountResult.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = signIntoPasskeyAccountResult.rawClientDataJSON.base64URLEncodedString()
        let signature = signIntoPasskeyAccountResult.signature.base64URLEncodedString()
        
        let verifyWebChallengeResult = try await postMessage(method: "verifyWebChallenge", arguments: [id, authenticatorData, clientDataJSON, signature])
        let userId = verifyWebChallengeResult as! String
        
        let wallet = try await postMessage(method: "loginV2", arguments: [userId, id, signIntoPasskeyAccountResult.userID.base64URLEncodedString()])
        self.wallet = Wallet(result: (wallet as! [String: Any]))
    }
    
    public func verify(verificationCode: String) async throws -> String {
        let result = try await postMessage(method: "verifyEmail", arguments: [verificationCode])
        let paths = (result as! String).split(separator: "/")
        let biometricsId = paths.last!.split(separator: "?").first!
        return String(biometricsId)
    }
    
    public func generatePasskey(email: String, biometricsId: String, authorizationController: AuthorizationController) async throws {
        var userHandle = Data(count: 32)
        let _ = userHandle.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        
        let userHandleEncoded = userHandle.base64URLEncodedString()
        let result = try await passkeysManager.createPasskeyAccount(authorizationController: authorizationController, username: email, userHandle: userHandle)
        
        let attestationObjectEncoded = result.rawAttestationObject!.base64URLEncodedString()
        let clientDataJSONEncoded = result.rawClientDataJSON.base64URLEncodedString()
        let credentialIDEncoded = result.credentialID.base64URLEncodedString()
        
        try await postMessage(method: "generatePasskeyV2", arguments: [attestationObjectEncoded, clientDataJSONEncoded, credentialIDEncoded, userHandleEncoded, biometricsId])
    }
    
    public func setup2FA() async throws -> String {
        let result = try await postMessage(method: "setup2FA", arguments: [])
        return (result as! [String: String])["uri"]!
    }
    
    public func enable2FA() async throws {
        let result = try await postMessage(method: "enable2FA", arguments: [])
    }

    public func is2FASetup() async throws -> Bool {
        let result = try await postMessage(method: "check2FAStatus", arguments: [])
        return (result as! [String: Any])["isSetup"]! as! Bool
    }
    
    public func resendVerificationCode() async throws {
        try await postMessage(method: "resendVerificationCode", arguments: [])
    }
    
    public func isFullyLoggedIn() async throws -> Bool {
        let result = try await postMessage(method: "isFullyLoggedIn", arguments: [])
        return result as! Bool
    }

    public func isSessionActive() async throws -> Bool {
        let result = try await postMessage(method: "isSessionActive", arguments: [])
        return result as? Bool ?? false
    }
    
    public func exportSession() async throws {
        let result = try await postMessage(method: "exportSession", arguments: [])
        print(result)
    }
    
    public func logout() async throws {
        try await postMessage(method: "logout", arguments: [])
        wallet = nil
    }
}

@available(iOS 16.4, *)
extension Capsule {
    public func createWallet(skipDistributable: Bool) async throws {
        let result = try await postMessage(method: "createWallet", arguments: [skipDistributable])
        let walletAndRecovery = (result as! [[String: Any]])[0]
        self.wallet = Wallet(result: (walletAndRecovery["wallet"] as! [String: String]))
    }
    
    public func fetchWallets() async throws -> [Wallet] {
        let result = try await postMessage(method: "fetchWallets", arguments: [])
        let wallets = (result as! [[String: Any]]).map { Wallet(result: $0)}
        return wallets
    }
    
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        let result = try await postMessage(method: "distributeNewWalletShare", arguments: [walletId, userShare])
        print(result)
    }
}

@available(iOS 16.4, *)
extension Capsule {
    public func signMessage(walletId: String, message: String) async throws -> String {
        let result = try await postMessage(method: "signMessage", arguments: [walletId, message.toBase64()])
        return (result as! [String: String])["signature"]!
    }
    
    public func signTransaction(walletId: String, rlpEncodedTx: String, chainId: String) async throws -> String {
        let result = try await postMessage(method: "signTransaction", arguments: [walletId, rlpEncodedTx.toBase64(), chainId])
        
        return (result as! [String: String])["signature"]!
    }
    
    public func sendTransaction(walletId: String, rlpEncodedTx: String, chainId: String) async throws -> String {
        let result = try await postMessage(method: "sendTransaction", arguments: [walletId, rlpEncodedTx.toBase64(), chainId])
        
        return (result as! [String: String])["signature"]!
    }
}


