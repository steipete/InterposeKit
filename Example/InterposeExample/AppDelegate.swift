//
//  AppDelegate.swift
//  InterposeExample
//
//  Copyright © 2020 Peter Steinberger. All rights reserved.
//

import UIKit
import InterposeKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        Interpose.isLoggingEnabled = true

        fixMacCatalystInputSystemSessionRace()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

/// We swizzle the `documentState` property of `RTIInputSystemSession` to make it thread safe.
/// Sample crasher: https://gist.github.com/steipete/504e79558d861211a3a9ff794e09c817
private func fixMacCatalystInputSystemSessionRace() {
    do {
        try Interpose.whenAvailable(["RTIInput", "SystemSession"]) {
            let lock = DispatchQueue(label: "com.steipete.document-state-hack")
            try $0.hook("documentState", { store in { `self` in
                lock.sync {
                    store((@convention(c) (AnyObject, Selector) -> AnyObject).self)(`self`, store.selector)
                }} as @convention(block) (AnyObject) -> AnyObject})

            try $0.hook("setDocumentState:", { store in { `self`, newValue in
                lock.sync {
                    store((@convention(c) (AnyObject, Selector, AnyObject) -> Void).self)(`self`, store.selector, newValue)
                }} as @convention(block) (AnyObject, AnyObject) -> Void})
        }
    } catch {
        print("Failed to fix input system: \(error).")
    }
}
