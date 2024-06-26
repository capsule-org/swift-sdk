/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
AccountStore manages account sign in and out.
*/

#if os(iOS) || os(macOS)

import AuthenticationServices
import SwiftUI
import Combine
import os

public extension Logger {
    static let authorization = Logger(subsystem: "Capsule Swift Example", category: "Passkeys Manager")
}

public enum AuthorizationHandlingError: Error {
    case unknownAuthorizationResult(ASAuthorizationResult)
    case otherError
}

extension AuthorizationHandlingError: LocalizedError {
    public var errorDescription: String? {
            switch self {
            case .unknownAuthorizationResult:
                return NSLocalizedString("Received an unknown authorization result.",
                                         comment: "Human readable description of receiving an unknown authorization result.")
            case .otherError:
                return NSLocalizedString("Encountered an error handling the authorization result.",
                                         comment: "Human readable description of an unknown error while handling the authorization result.")
            }
        }
}

public final class PasskeysManager: NSObject, ASAuthorizationControllerDelegate {
    public weak var presentationContextProvider: ASAuthorizationControllerPresentationContextProviding?
    
    public func signIntoPasskeyAccount(authorizationController: AuthorizationController,
                                       challenge: String,
                                       options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let authorizationResult = try await authorizationController.performRequests(
                signInRequests(challenge: challenge),
                options: options
        )
        
        switch authorizationResult {
        case let .passkeyAssertion(passkeyAssertion):
            return passkeyAssertion
        default:
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    }
    
    public func createPasskeyAccount(authorizationController: AuthorizationController, username: String, userHandle: Data,
                                     options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let authorizationResult = try await authorizationController.performRequests(
                [passkeyRegistrationRequest(username: username, userHandle: userHandle)],
                options: options
        )
        
        switch authorizationResult {
        case let .passkeyRegistration(passkeyRegistration):
            return passkeyRegistration
        default:
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
        
//        return try await withCheckedThrowingContinuation { continuation in
//            registrationContinuation = continuation
//        }
//        do {
//            let authorizationResult = try await authorizationController.performRequests(
//                    [passkeyRegistrationRequest(username: username, userHandle: userHandle)],
//                    options: options
//            )
//            try await handleAuthorizationResult(authorizationResult, username: username)
//        } catch let authorizationError as ASAuthorizationError where authorizationError.code == .canceled {
//            // The user cancelled the registration.
//            Logger.authorization.log("The user cancelled passkey registration.")
//        } catch let authorizationError as ASAuthorizationError {
//            // Some other error occurred occurred during registration.
//            Logger.authorization.error("Passkey registration failed. Error: \(authorizationError.localizedDescription)")
//        } catch AuthorizationHandlingError.unknownAuthorizationResult(let authorizationResult) {
//            // Received an unknown response.
//            Logger.authorization.error("""
//            Passkey registration handling failed. \
//            Received an unknown result: \(String(describing: authorizationResult))
//            """)
//        } catch {
//            // Some other error occurred while handling the registration.
//            Logger.authorization.error("""
//            Passkey registration handling failed. \
//            Caught an unknown error during passkey registration or handling: \(error.localizedDescription).
//            """)
//        }
    }
    // MARK: - Private

    private static let relyingPartyIdentifier = "optimum-seagull-discrete.ngrok-free.app"
    
    private func passkeyChallenge() async -> Data {
        Data("passkey challenge".utf8)
    }

    private func passkeyAssertionRequest(challenge: String) async -> ASAuthorizationRequest {
        await ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
            .createCredentialAssertionRequest(challenge: Data(base64URLEncoded: challenge)!)
    }

    private func passkeyRegistrationRequest(username: String, userHandle: Data) async -> ASAuthorizationRequest {
        await ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyIdentifier)
           .createCredentialRegistrationRequest(challenge: passkeyChallenge(), name: username, userID: userHandle)
    }

    private func signInRequests(challenge: String) async -> [ASAuthorizationRequest] {
        await [passkeyAssertionRequest(challenge: challenge), ASAuthorizationPasswordProvider().createRequest()]
    }
    
    private func handleAuthorizationResult(_ authorizationResult: ASAuthorizationResult, username: String? = nil) async throws {
        switch authorizationResult {
        case let .passkeyAssertion(passkeyAssertion):
            // The login was successful.
            Logger.authorization.log("Passkey authorization succeeded: \(passkeyAssertion)")
            guard let username = String(bytes: passkeyAssertion.userID, encoding: .utf8) else {
                fatalError("Invalid credential: \(passkeyAssertion)")
            }
        case let .passkeyRegistration(passkeyRegistration):
            // The registration was successful.
            Logger.authorization.log("Passkey registration succeeded: \(passkeyRegistration)")
        default:
            Logger.authorization.error("Received an unknown authorization result.")
            // Throw an error and return to the caller.
            throw AuthorizationHandlingError.unknownAuthorizationResult(authorizationResult)
        }
    }
}

#endif // os(iOS) || os(macOS)
