
# Capsule Swift SDK

  

[![Swift](https://img.shields.io/badge/Swift-5.7+-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.7+-Orange?style=flat-square)
[![iOS](https://img.shields.io/badge/iOS-16.4+-yellowgreen?style=flat-square)](https://img.shields.io/badge/iOS-16.4+-Green?style=flat-square)
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)

  
## Prerequisites
### Request an API Key & Send us Your Team ID & Bundle ID
Your team id can be found from [Apple's developer portal](https://developer.apple.com/account/resources/certificates/list) in the top right corner of the Certificates, Identifiers & Profiles section.

<img width="1262" alt="Team ID" src="https://github.com/capsule-org/swift-sdk/assets/4346395/8804c237-5805-49e8-b7ef-845833646261">

Your bundle identifier can be found here

<img width="1547" alt="Bundle Identifier" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84827d38-8477-422a-8e66-6c3ac6819095">

**To request an API Key and send us your team and bundle ids, please fill out [this form](https://usecapsule.com/api)**

## Installation

  

### Swift Package Manager

  

The [Swift Package Manager](https://swift.org/package-manager/) is a tool for automating the distribution of Swift code and is integrated into the `swift` compiler.

  

Once you have your Swift package set up, adding CapsuleSwift as a dependency is as easy as adding it to the `dependencies` value of your `Package.swift` or the Package list in Xcode.

  

```swift

dependencies: [

.package(url: "https://github.com/capsule-org/swift-sdk.git", .upToNextMajor(from: "0.0.1"))

]

```

  

Normally you'll want to depend on the `CapsuleSwift` target:

  

```swift

.product(name: "CapsuleSwift", package: "CapsuleSwift")

```

  

## Configuring You Project

  

CapsuleSwift utilizes native passkeys for authentication and wallet information. In order to use native passkeys in your app you will need several things

  

### Associated Domains



Under **Targets**->**AppName**->**Signing & Capabilities**, click on the **+Capability** button.

<img width="1483" alt="Capability" src="https://github.com/capsule-org/swift-sdk/assets/4346395/296ade64-552a-4833-9d24-4059335e82d2">

From the prompt that appears, search for and select **Associated Domains**

<img width="702" alt="Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/6570acd4-75a6-43d2-92cc-2da713a51246">


> **Note:** In order to add the associated domains capability to your project, you cannot use a personal team for the purposes of signing. If you are, you need to set up a company team with Apple.

In the associated domains section that appears after adding it, you will need to add two domains

1. webcredentials:app.beta.usecapsule.com
2. webcredentials:app.usecapsule.com

<img width="874" alt="Add Associated Domains" src="https://github.com/capsule-org/swift-sdk/assets/4346395/84c010e3-1377-4be4-ba74-6644781d78a4">
<img width="370" alt="AD Filled Out" src="https://github.com/capsule-org/swift-sdk/assets/4346395/3fb7a653-b90d-47b3-ae05-dd75905d3458">


This will allow you to use passkeys that have been created on any app that uses the Capsule system, so if your users already have a Capsule wallet they will be able to use it in your app.  


## Using Capsule Swift

  

### Introduction

  

CapsuleSwift provides an interface to Capsule services from within iOS applications using SwiftUI (Support for UIKit comming soon).

  

### Configuring

  

To configure the capsule instance, you will need to create an instance of the capsule object as well as the globally available authorizationController environment object. This will be needed in several functions later on. If you need an API Key, please reach out to the Capsule Team.

  

You will also need to add an instance of the CapsuleWebView to your view passing in the instance of Capsule that we just created, and set it to hidden so that it doesn't appear on screen. It is recommended to use a ZStack and set this as the topmost view, which will hide it behind all other views that render on the screen.

  

```swift

struct UserAuthView: View {

@StateObject var capsule = CapsuleSwift.Capsule(environment: CapsuleEnvironment.beta(jsBridgeUrl: nil), apiKey: "<YOUR_API_KEY>")

@Environment(\.authorizationController) private var authorizationController

var body: some View {

ZStack {

CapsuleWebView(viewModel: capsule).hidden()

...

```

  

### Creating a User

  

To create a user, you should first check in the provided email address exists, and if it does not then create it

  

```swift

Button("Sign Up") {

Task.init {

let userExists = try! await capsule.checkIfUserExists(email: email)

if userExists {

return

}

try! await capsule.createUser(email: email)

...

}

}

```

  

Upon success, the user should receive an email with a 6 digit verification pin. Call the verify function with the verification code acquired from this step. This will return a biometricsId which will be necessary to pass to the next function, generatePasskey.

  

Generate passkey takes in the authorizationController that was set up earlier. This is necessary to be able to allow the application to present the Passkey modals for creating and selecting a Passkey.

  

After generating the passkey, the last step is to create a wallet.

  

```swift

Button("Verify") {

Task.init {

let biometricsId = try! await capsule.verify(verificationCode: code)

try! await capsule.generatePasskey(email: email, biometricsId: biometricsId, authorizationController: authorizationController)

try! await capsule.createWallet(skipDistributable: false)

}

}

```

  

After the wallet has been created, it will be set in the Capsule object as a Published var.

  

### Signing a Message

  

To sign a message, all you need to do is pass in the id of the wallet you would like to use which can be obtained from the capsule.wallet property, and the text that you would like to sign. This will produce a messageSignature.

  

```swift

Button("Sign Message") {

Task.init {

let messageSignature = try! await capsule.signMessage(walletId: wallet.id, message: "Some message to sign")

...

}

}

```
