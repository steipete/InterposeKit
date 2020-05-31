# InterposeKit

[![SwiftPM](https://github.com/steipete/InterposeKit/workflows/SwiftPM/badge.svg)](https://github.com/jsteipete/InterposeKit/actions?query=workflow%3ASwiftPM)
[![xcodebuild](https://github.com/steipete/InterposeKit/workflows/xcodebuild/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3Axcodebuild)
[![pod lib lint](https://github.com/steipete/InterposeKit/workflows/pod%20lib%20lint/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3A%22pod+lib+lint%22)
![Xcode 11.4+](https://img.shields.io/badge/Xcode-11.4%2B-blue.svg)
![Swift 5.2+](https://img.shields.io/badge/Swift-5.2%2B-orange.svg)
<!--
[![codecov](https://codecov.io/gh/steipete/InterposeKit/branch/master/graph/badge.svg)](https://codecov.io/gh/steipete/InterposeKit) -->

InterposeKit is a modern library to swizzle elegantly in Swift. It is fully written in Swift 5.2+ and works on `@objc dynamic` Swift functions or Objective-C instance methods. API documentation available at [steipete.github.io/InterposeKit](https://steipete.github.io/InterposeKit/)

Instead of [adding new methods and exchanging implementations](https://nshipster.com/method-swizzling/), this library replaces the implementation directly.  
This avoids some of [the usual problems with swizzling](https://pspdfkit.com/blog/2019/swizzling-in-swift/).

You can call the original implementation and add code before, instead or after a method call.  
This is similart o the [Aspects library](https://github.com/steipete/Aspects).

## Usage

Let's say you want to amend `sayHi` from `TestClass`:

```swift

class TestClass: NSObject {
    @objc dynamic func sayHi() -> String {
        print("Calling sayHi")
        return "Hi there 👋"
    }
}

try Interposer(TestClass.self) {
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

## FAQ

### Why didn't you call it Interpose? "Kit" feels so old-school.
Naming it Interpose was the plan, but then [SR-898](https://bugs.swift.org/browse/SR-898) came. While having a class with the same name as the module works [in most cases](https://forums.swift.org/t/frameworkname-is-not-a-member-type-of-frameworkname-errors-inside-swiftinterface/28962), [this breaks](https://twitter.com/BalestraPatrick/status/1260928023357878273) when you enable build-for-distribution. There's some [discussion](https://forums.swift.org/t/pitch-fully-qualified-name-syntax/28482/81) to get that fixed, but this will be more towards end of 2020, if even.

### I want to hook into Swift! You made another ObjC swizzle thingy, why?
UIKit and AppKit won't go away, and the bugs won't go away either. I see this as a rarely-needed instrument to fix system-level issues. There are ways to do some of that in Swift, but that's a separate (and much more difficult!) project. 

### Can I ship this?
Yes, absolutely. The goal for this one prokect is a simple library that doesn't try to be too smart. I did this in [Aspects](https://github.com/steipete/Aspects) and while I loved this to no end, it's problematic and can cause side-effects with other code that tries to be clever. InterposeKit is boring, so you don't have to worry about conditions like "We added New Relic to our app and now [your thing crashes](https://github.com/steipete/Aspects/issues/21)".

### It does not do X
Pull Requests welcome! You might wanna open a draft before to lay out what you plan, I want to keep the feature-set minimal so it stays simple and no-magic.

## Installation

Building InterposeKit requires Xcode 11.4+ or a Swift 5.2+ toolchain with the Swift Package Manager.

### Swift Package Manager

Add `.package(url: "https://github.com/steipete/InterposeKit.git", from: "0.0.1")` to your
`Package.swift` file's `dependencies`.

### CocoaPods

Add `pod 'InterposeKit'` to your `Podfile`.

### Carthage

Add `github "steipete/InterposeKit"` to your `Cartfile`.

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

## Thanks

Special thanks to [JP Simard](https://github.com/jpsim/Yams) who did such a great job in setting up [Yams](https://github.com/jpsim/Yams) with GitHub Actions - this was extremely helpful to build CI here fast.

## License

InterposeKit is MIT Licensed.
