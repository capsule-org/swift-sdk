//
//  File.swift
//  
//
//  Created by Brian Corbin on 6/3/24.
//

import Foundation

public enum CapsuleEnvironment: Hashable {
    case dev(relyingPartyId: String, jsBridgeUrl: URL?)
    case sandbox(jsBridgeUrl: URL?)
    case beta(jsBridgeUrl: URL?)
    case prod(jsBridgeUrl: URL?)

    var relyingPartyId: String {
        switch self {
        case .dev(let relyingPartyId, _):
            return relyingPartyId
        case .sandbox(_):
            return "app.sandbox.usecapsule.com"
        case .beta(_):
            return "app.beta.usecapsule.com"
        case .prod(_):
            return "app.usecapsule.com"
        }
    }
    
    var jsBridgeUrl: URL {
        switch self {
        case .dev(_, let jsBridgeUrl):
            return jsBridgeUrl ?? URL(string: "http://localhost:3004")!
        case .sandbox(let jsBridgeUrl):
            return jsBridgeUrl ?? URL(string: "https://js-bridge.sandbox.usecapsule.com/")!
        case .beta(let jsBridgeUrl):
            return jsBridgeUrl ?? URL(string: "https://js-bridge.beta.usecapsule.com/")!
        case .prod(let jsBridgeUrl):
            return jsBridgeUrl ?? URL(string: "https://js-bridge.usecapsule.com/")!
        }
    }
    
    var name: String {
        switch self {
        case .dev(_ ,_):
            return "DEV"
        case .sandbox(_):
            return "SANDBOX"
        case .beta(_):
            return "BETA"
        case .prod(_):
            return "PROD"
        }
    }
}
