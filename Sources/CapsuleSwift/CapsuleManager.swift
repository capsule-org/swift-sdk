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

enum CapsuleError: Error {
    case bridgeError(String)
    case bridgeTimeoutError
}

extension CapsuleError: CustomStringConvertible {
    var description: String {
        switch self {
        case .bridgeError(let info):
            return "The following error happened while the javascript bridge was executing: \(info)"
        case .bridgeTimeoutError:
            return "The javascript bridge did not respond in time and the continuation has been cancelled."
        }
    }
}

@available(iOS 16.4, *)
public class CapsuleManager: NSObject, ObservableObject {
    // MARK: - Public
    @MainActor @Published public var wallets: [Wallet] = []
    @MainActor @Published public var sessionState: CapsuleSessionState = .unknown
    
    public static let packageVersion = "0.0.3"
    public var environment: CapsuleEnvironment {
        didSet {
            self.passkeysManager.relyingPartyIdentifier = environment.relyingPartyId
        }
    }
    public var apiKey: String
    
    public var webView: WKWebView = WKWebView(frame: CGRect.zero)
    
    
    // MARK: - Private
    private let passkeysManager: PasskeysManager
    public private(set) var isCapsuleInitialized: Bool = false
    private var continuation: CheckedContinuation<Any?, Error>?
    private var messageQueue: [(String, [Encodable], CheckedContinuation<Any?, Error>)] = []
    private var isProcessingMessage = false
    
    // MARK: - Internal
    public init(environment: CapsuleEnvironment, apiKey: String) {
        self.environment = environment
        self.apiKey = apiKey
        self.passkeysManager = PasskeysManager(relyingPartyIdentifier: environment.relyingPartyId)
        
        super.init()
        webView.configuration.userContentController.add(self, name: "callback")
        webView.navigationDelegate = self
        webView.load(URLRequest(url: environment.jsBridgeUrl))
    }
    
    public func initCapsule() {
        let script = """
          window.postMessage({
            messageType: 'Capsule#init',
            arguments: {
              environment: '\(environment.name)',
              apiKey: '\(apiKey)',
              platform: 'iOS',
              package: '\(Self.packageVersion)'
            }
          });
        """
        
        webView.evaluateJavaScript(script)
    }
    
    @MainActor
    @discardableResult
    private func postMessage(method: String, arguments: [Encodable]) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            messageQueue.append((method, arguments, continuation))
            processNextMessageIfNeeded()
        }
    }

    private func processNextMessageIfNeeded() {
        guard !isProcessingMessage, let (method, arguments, _) = messageQueue.first else { return }
        
        isProcessingMessage = true
        let script = """
          window.postMessage({
            'messageType': 'Capsule#invokeMethod',
            'methodName': '\(method)',
            'arguments': \(arguments)
          });
        """

        webView.evaluateJavaScript(script)
    }
    
    private func completeCurrentMessage(with result: Result<Any?, Error>) {
        guard let (_, _, continuation) = messageQueue.first else { return }
        
        messageQueue.removeFirst()
        isProcessingMessage = false
        
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        
        processNextMessageIfNeeded()
    }
}

// MARK: - WKNavigationDelegate

@available(iOS 16.4, *)
extension CapsuleManager: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            initCapsule()
            guard let active = try? await isSessionActive(), active else {
                sessionState = .inactive
                return
            }
            guard let loggedIn = try? await isFullyLoggedIn(), loggedIn else {
                sessionState = .active
                return
            }
            sessionState = .activeLoggedIn
        }
    }
}

// MARK: - WKScriptMessageHandler

@available(iOS 16.4, *)
extension CapsuleManager: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let resp = message.body as? [String: Any],
              let method = resp["method"] as? String else {
            completeCurrentMessage(with: .failure(CapsuleError.bridgeError("Invalid response format")))
            return
        }

        if let error = resp["error"] as? String {
            completeCurrentMessage(with: .failure(CapsuleError.bridgeError("\(method): \(error)")))
        } else if resp["error"] != nil {
            completeCurrentMessage(with: .failure(CapsuleError.bridgeError("\(method): Error occurred, but details are not available")))
        } else {
            if (method == "Capsule#init") {
                isCapsuleInitialized = true
            }
            completeCurrentMessage(with: .success(resp["responseData"]))
        }
    }
}

// MARK: - Account

@available(iOS 16.4, *)
extension CapsuleManager {
    
    public func checkIfUserExists(email: String) async throws -> Bool {
        let result = try await postMessage(method: "checkIfUserExists", arguments: [email])
        return try decodeResult(result, expectedType: Bool.self, method: "checkIfUserExists")
    }
    
    public func createUser(email: String) async throws {
        try await postMessage(method: "createUser", arguments: [email])
    }
    
    @MainActor
    public func login(authorizationController: AuthorizationController) async throws {
        let getWebChallengeResult = try await postMessage(method: "getWebChallenge", arguments: [])
        let challenge = try decodeDictionaryResult(getWebChallengeResult, expectedType: String.self, method: "getWebChallenge", key: "challenge")
        
        let signIntoPasskeyAccountResult = try await passkeysManager.signIntoPasskeyAccount(authorizationController: authorizationController, challenge: challenge)
        
        let id = signIntoPasskeyAccountResult.credentialID.base64URLEncodedString()
        let authenticatorData = signIntoPasskeyAccountResult.rawAuthenticatorData.base64URLEncodedString()
        let clientDataJSON = signIntoPasskeyAccountResult.rawClientDataJSON.base64URLEncodedString()
        let signature = signIntoPasskeyAccountResult.signature.base64URLEncodedString()
        
        let verifyWebChallengeResult = try await postMessage(method: "verifyWebChallenge", arguments: [id, authenticatorData, clientDataJSON, signature])
        let userId = try decodeResult(verifyWebChallengeResult, expectedType: String.self, method: "verifyWebChallenge")
        
        let _ = try await postMessage(method: "loginV2", arguments: [userId, id, signIntoPasskeyAccountResult.userID.base64URLEncodedString()])
        self.wallets = try await fetchWallets()
        sessionState = .activeLoggedIn
    }
    
    public func verify(verificationCode: String) async throws -> String {
        let result = try await postMessage(method: "verifyEmail", arguments: [verificationCode])
        let resultString = try decodeResult(result, expectedType: String.self, method: "verifyEmail")
        
        let paths = resultString.split(separator: "/")
        
        guard let lastPath = paths.last,
              let biometricsId = lastPath.split(separator: "?").first else {
            throw CapsuleError.bridgeError("Invalid path format in result")
        }
        
        return String(biometricsId)
    }
    
    public func generatePasskey(email: String, biometricsId: String, authorizationController: AuthorizationController) async throws {
        var userHandle = Data(count: 32)
        let _ = userHandle.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        
        let userHandleEncoded = userHandle.base64URLEncodedString()
        let result = try await passkeysManager.createPasskeyAccount(authorizationController: authorizationController,
                                                                    username: email, userHandle: userHandle)
        
        let attestationObjectEncoded = result.rawAttestationObject!.base64URLEncodedString()
        let clientDataJSONEncoded = result.rawClientDataJSON.base64URLEncodedString()
        let credentialIDEncoded = result.credentialID.base64URLEncodedString()
        
        try await postMessage(method: "generatePasskeyV2",
                              arguments: [attestationObjectEncoded, clientDataJSONEncoded, credentialIDEncoded, userHandleEncoded, biometricsId])
    }
    
    public func setup2FA() async throws -> String {
        let result = try await postMessage(method: "setup2FA", arguments: [])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "setup2FA", key: "uri")
    }
    
    public func enable2FA() async throws {
        try await postMessage(method: "enable2FA", arguments: [])
    }
    
    public func is2FASetup() async throws -> Bool {
        let result = try await postMessage(method: "check2FAStatus", arguments: [])
        return try decodeDictionaryResult(result, expectedType: Bool.self, method: "check2FAStatus", key: "isSetup")
    }
    
    public func resendVerificationCode() async throws {
        _ = try await postMessage(method: "resendVerificationCode", arguments: [])
    }
    
    public func isFullyLoggedIn() async throws -> Bool {
        let result = try await postMessage(method: "isFullyLoggedIn", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isFullyLoggedIn")
    }
    
    public func isSessionActive() async throws -> Bool {
        let result = try await postMessage(method: "isSessionActive", arguments: [])
        return try decodeResult(result, expectedType: Bool.self, method: "isSessionActive")
    }
    
    public func exportSession() async throws -> String {
        let result = try await postMessage(method: "exportSession", arguments: [])
        return try decodeResult(result, expectedType: String.self, method: "exportSession")
    }
    
    @MainActor
    public func logout() async throws {
        try await postMessage(method: "logout", arguments: [])
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let dateFrom = Date(timeIntervalSince1970: 0)
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: dateFrom)
        wallets = []
        self.sessionState = .inactive
    }
}

// MARK: - Wallets

@available(iOS 16.4, *)
extension CapsuleManager {
    @MainActor
    public func createWallet(skipDistributable: Bool) async throws {
        let _ = try await postMessage(method: "createWallet", arguments: ["EVM", skipDistributable])
        self.wallets = try await fetchWallets()
        self.sessionState = .activeLoggedIn
    }
    
    public func fetchWallets() async throws -> [Wallet] {
        let result = try await postMessage(method: "fetchWallets", arguments: [])
        let walletsData = try decodeResult(result, expectedType: [[String: Any]].self, method: "fetchWallets")
        return walletsData.map { Wallet(result: $0) }
    }
    
    public func distributeNewWalletShare(walletId: String, userShare: String) async throws {
        try await postMessage(method: "distributeNewWalletShare", arguments: [walletId, userShare])
    }
    
    public func getEmail() async throws -> String {
        let result = try await postMessage(method: "getEmail", arguments: [])
        let email = try  decodeResult(result, expectedType: String.self, method: "getEmail")
        return email
    }
}

// MARK: - Transactions

@available(iOS 16.4, *)
extension CapsuleManager {
    public func signMessage(walletId: String, message: String) async throws -> String {
        let result = try await postMessage(method: "signMessage", arguments: [walletId, message.toBase64()])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signMessage", key: "signature")
    }
    
    public func signTransaction(walletId: String, rlpEncodedTx: String, chainId: String) async throws -> String {
        let result = try await postMessage(method: "signTransaction", arguments: [walletId, rlpEncodedTx.toBase64(), chainId])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "signTransaction",  key: "signature")
    }
    
    public func sendTransaction(walletId: String, rlpEncodedTx: String, chainId: String) async throws -> String {
        let result = try await postMessage(method: "sendTransaction", arguments: [walletId, rlpEncodedTx.toBase64(), chainId])
        return try decodeDictionaryResult(result, expectedType: String.self, method: "sendTransaction", key: "signature")
    }
}


// MARK: - Generic Helpers

@available(iOS 16.4, *)
extension CapsuleManager {
    func decodeResult<T>(_ result: Any?, expectedType: T.Type, method: String) throws -> T {
        guard let value = result as? T else {
            throw CapsuleError.bridgeError("METHOD_ERROR<\(method)>: Invalid result format expected \(T.self)")
        }
        return value
    }
    
    func decodeDictionaryResult<T>(_ result: Any?, expectedType: T.Type, method: String, key: String) throws -> T {
        let dict = try decodeResult(result, expectedType: [String: Any].self, method: method)
        guard let value = dict[key] as? T else {
            throw CapsuleError.bridgeError("KEY_ERROR<\(method)-\(key)>: Missing or invalid key result")
        }
        return value
    }
}
