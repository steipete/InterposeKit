# InterposeKit

[![SwiftPM](https://github.com/steipete/InterposeKit/workflows/SwiftPM/badge.svg)](https://github.com/jsteipete/InterposeKit/actions?query=workflow%3ASwiftPM)
[![xcodebuild](https://github.com/steipete/InterposeKit/workflows/xcodebuild/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3Axcodebuild)
[![pod lib lint](https://github.com/steipete/InterposeKit/workflows/pod%20lib%20lint/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3A%22pod+lib+lint%22)
[![codecov](https://codecov.io/gh/steipete/InterposeKit/branch/master/graph/badge.svg)](https://codecov.io/gh/steipete/InterposeKit)
![Xcode 11.5+](https://img.shields.io/badge/Xcode-11.5%2B-blue.svg)
![Swift 5.2+](https://img.shields.io/badge/Swift-5.2%2B-orange.svg)

Interpose is a modern library to swizzle elegant in Swift. Unlike the usual sample, code, this library replaces the implementation, so you avoid some of [the usual problems with swizzling](https://pspdfkit.com/blog/2019/swizzling-in-swift/).

Since you have full control over the original implementation, it's easy to add code before, instead or after a method call - similar to my [Aspects library](https://github.com/steipete/Aspects).

Let's say you want to amend `sayHi` from `TestClass`:

```swift

class TestClass: NSObject {
    @objc dynamic func sayHi() -> String {
        print("Calling sayHi")
        return "Hi there 👋"
    }
}

try Interposer.interpose(TestClass.self) {
    try $0.hook(#selector(TestClass.sayHi), { store in { `self` in
        print("Before Interposing \(`self`)")

        let string = store((@convention(c) (AnyObject, Selector) -> String).self)(`self`, store.selector)

        print("After Interposing \(`self`)")
        return string + testSwizzleAddition
        }
        as @convention(block) (AnyObject) -> String})
}
```

Here's what we get when calling `print(TestClass().sayHi())` 
```
[Interposer] Swizzled -[TestClass.sayHi] IMP: 0x000000010d9f4430 -> 0x000000010db36020
Before Interposing <InterposeTests.TestClass: 0x7fa0b160c1e0>
Calling sayHi
After Interposing <InterposeTests.TestClass: 0x7fa0b160c1e0>
Hi there 👋 and Interpose
```
## Installation

Building InterposeKit requires Xcode 11.4+ or a Swift 5.2+ toolchain with the Swift Package Manager.

### Swift Package Manager

Add `.package(url: "https://github.com/steipete/InterposeKit.git", from: "0.0.1")` to your
`Package.swift` file's `dependencies`.

### CocoaPods

Add `pod 'InterposeKit'` to your `Podfile`.

### Carthage

Add `github "steipete/InterposeKit"` to your `Cartfile`.

## Key Facts

- Interpose directly modifies the implementaton of a `Method`, which is [better than selector-based swizzling]((https://pspdfkit.com/blog/2019/swizzling-in-swift/)).
- Pure Swift, no `NSInvocation`, which requires boxing and can be slow.
- No Type checking. If you have a typo or forget a `convention` part, this will crash at runtime.
- Yes, you have to type the resulting type twice This is a tradeoff, else we need NSInvocation or assembly 
- Delayed Interposing helps when a class is loaded at runtime. This is useful for [Mac Catalyst](https://steipete.com/posts/mac-catalyst-crash-hunt/)

## Delayed Hooking

Sometimes it can be necessary to hook a class deep in a system framework, which is loaded at a later time. Interpose has a solution for this and uses a hook in the dynamic linker to be notified whenever new classes are loaded.

```swift
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
```

## Improvement Ideas

- Write proposal to allow to [convert the calling convention of existing types](https://twitter.com/steipete/status/1266799174563041282?s=21).
- Use the C block struct to perfom type checking between Method type and C type (I do that in  [Aspects library](https://github.com/steipete/Aspects)), it's still a runtime crash but could be at hook time, not when we call it.
- Add object-based hooking with dynamic subclassing (Aspects again)
- Add dyld_interpose to hook pure C functions
- Combine Promise-API for `Interpose.whenAvailable` for better error bubbling.
- Experiment with Swift hooking? 🤡
- I'm sure there's more - Pull Requests or [comments](https://twitter.com/steipete) very welcome!
- Test against Swift Nightly as Chron

Make this happen:
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
![CocoaPods](https://img.shields.io/cocoapods/v/SwiftyJSON.svg)


## License

MIT Licensed
