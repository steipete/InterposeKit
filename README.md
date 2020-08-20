<img src="https://raw.githubusercontent.com/steipete/InterposeKit/master/logo.png" width="60%" alt="InterposeKit"/>

[![SwiftPM](https://github.com/steipete/InterposeKit/workflows/SwiftPM/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3ASwiftPM)
[![xcodebuild](https://github.com/steipete/InterposeKit/workflows/xcodebuild/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3Axcodebuild)
[![pod lib lint](https://github.com/steipete/InterposeKit/workflows/pod%20lib%20lint/badge.svg)](https://github.com/steipete/InterposeKit/actions?query=workflow%3A%22pod+lib+lint%22)
![Xcode 11.4+](https://img.shields.io/badge/Xcode-11.4%2B-blue.svg)
![Swift 5.2+](https://img.shields.io/badge/Swift-5.2%2B-orange.svg)
<!--
[![codecov](https://codecov.io/gh/steipete/InterposeKit/branch/master/graph/badge.svg)](https://codecov.io/gh/steipete/InterposeKit) -->

InterposeKit is a modern library to swizzle elegantly in Swift, supporting hooks on classes and individual objects. It is [well-documented](http://interposekit.com/), [tested](https://github.com/steipete/InterposeKit/actions?query=workflow%3ASwiftPM), written in "pure" Swift 5.2 and works on `@objc dynamic` Swift functions or Objective-C instance methods. The Inspiration for InterposeKit was [a race condition in Mac Catalyst](https://steipete.com/posts/mac-catalyst-crash-hunt/), which required tricky swizzling to fix, I also wrote up  [implementation thoughts on my blog](https://steipete.com/posts/interposekit/).

Instead of [adding new methods and exchanging implementations](https://nshipster.com/method-swizzling/) based on [`method_exchangeImplementations`](https://developer.apple.com/documentation/objectivec/1418769-method_exchangeimplementations), this library replaces the implementation directly using [`class_replaceMethod`](https://developer.apple.com/documentation/objectivec/1418677-class_replacemethod). This avoids some of [the usual problems with swizzling](https://pspdfkit.com/blog/2019/swizzling-in-swift/).

You can call the original implementation and add code before, instead or after a method call.  
This is similar to the [Aspects library](https://github.com/steipete/Aspects), but doesn't yet do dynamic subclassing.

Compare: [Swizzling a property without helper and with InterposeKit](https://gist.github.com/steipete/f955aaa0742021af15add0133d8482b9) 

## Usage

Let's say you want to amend `sayHi` from `TestClass`:

```swift
class TestClass: NSObject {
    // Functions need to be marked as `@objc dynamic` or written in Objective-C.
    @objc dynamic func sayHi() -> String {
        print("Calling sayHi")
        return "Hi there 👋"
    }
}

let interposer = try Interpose(TestClass.self) {
    try $0.prepareHook(
        #selector(TestClass.sayHi),
        methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
        hookSignature: (@convention(block) (AnyObject) -> String).self) {
            store in { `self` in
                print("Before Interposing \(`self`)")
                let string = store.original(`self`, store.selector) // free to skip
                print("After Interposing \(`self`)")
                return string + "and Interpose"
            }
    }
}

// Don't need the hook anymore? Undo is built-in!
interposer.revert()
```

Want to hook just a single instance? No problem!

```swift
let hook = try testObj.hook(
    #selector(TestClass.sayHi),
    methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
    hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { `self` in
        return store.original(`self`, store.selector) + "just this instance"
        }
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

## Key Features

- Interpose directly modifies the implementation of a `Method`, which is [safer than selector-based swizzling]((https://pspdfkit.com/blog/2019/swizzling-in-swift/)).
- Interpose works on classes and individual objects.
- Hooks can easily be undone via calling `revert()`. This also checks and errors if someone else changed stuff in between.
- Mostly Swift, no `NSInvocation`, which requires boxing and can be slow.
- No Type checking. If you have a typo or forget a `convention` part, this will crash at runtime.
- Yes, you have to type the resulting type twice This is a tradeoff, else we need `NSInvocation`.
- Delayed Interposing helps when a class is loaded at runtime. This is useful for [Mac Catalyst](https://steipete.com/posts/mac-catalyst-crash-hunt/).

## Object Hooking

InterposeKit can hook classes and object. Class hooking is similar to swizzling, but object-based hooking offers a variety of new ways to set hooks. This is achieved via creating a dynamic subclass at runtime. 

Caveat: Hooking will fail with an error if the object uses KVO. The KVO machinery is fragile and it's to easy to cause a crash. Using KVO after a hook was created is supported and will not cause issues.

## Various ways to define the signature

Next to using  `methodSignature` and `hookSignature`, following variants to define the signature are also possible:

### methodSignature + casted block
```
let interposer = try Interpose(testObj) {
    try $0.hook(
        #selector(TestClass.sayHi),
        methodSignature: (@convention(c) (AnyObject, Selector) -> String).self) { store in { `self` in
            let string = store.original(`self`, store.selector)
            return string + testString
            } as @convention(block) (AnyObject) -> String }
}
```

### Define type via store object
```
// Functions need to be `@objc dynamic` to be hookable.
let interposer = try Interpose(testObj) {
    try $0.hook(#selector(TestClass.returnInt)) { (store: TypedHook<@convention(c) (AnyObject, Selector) -> Int, @convention(block) (AnyObject) -> Int>) in {

        // You're free to skip calling the original implementation.
        let int = store.original($0, store.selector)
        return int + returnIntOverrideOffset
        }
    }
}
```

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
UIKit and AppKit won't go away, and the bugs won't go away either. I see this as a rarely-needed instrument to fix system-level issues. There are ways to do some of that in Swift, but that's a separate (and much more difficult!) project. (See [Dynamic function replacement #20333](https://github.com/apple/swift/pull/20333) aka `@_dynamicReplacement` for details.)

### Can I ship this?
Yes, absolutely. The goal for this one project is a simple library that doesn't try to be too smart. I did this in [Aspects](https://github.com/steipete/Aspects) and while I loved this to no end, it's problematic and can cause side-effects with other code that tries to be clever. InterposeKit is boring, so you don't have to worry about conditions like "We added New Relic to our app and now [your thing crashes](https://github.com/steipete/Aspects/issues/21)".

### It does not do X!
Pull Requests welcome! You might wanna open a draft before to lay out what you plan, I want to keep the feature-set minimal so it stays simple and no-magic.

## Installation

Building InterposeKit requires Xcode 11.4+ or a Swift 5.2+ toolchain with the Swift Package Manager.

### Swift Package Manager

Add `.package(url: "https://github.com/steipete/InterposeKit.git", from: "0.0.1")` to your
`Package.swift` file's `dependencies`.

### CocoaPods

[InterposeKit is on CocoaPods](https://cocoapods.org/pods/InterposeKit). Add `pod 'InterposeKit'` to your `Podfile`.

### Carthage

Add `github "steipete/InterposeKit"` to your `Cartfile`.

## Improvement Ideas

- Write proposal to allow to [convert the calling convention of existing types](https://twitter.com/steipete/status/1266799174563041282?s=21).
- Use the C block struct to perform type checking between Method type and C type (I do that in  [Aspects library](https://github.com/steipete/Aspects)), it's still a runtime crash but could be at hook time, not when we call it.
- Add a way to get all current hooks from an object/class.
- Add a way to revert hooks without super helper.
- Add a way to apply multiple hooks to classes
- Enable hooking of class methods.
- Add [dyld_dynamic_interpose](https://twitter.com/steipete/status/1258482647933870080) to hook pure C functions
- Combine Promise-API for `Interpose.whenAvailable` for better error bubbling.
- Experiment with [Swift function hooking](https://github.com/rodionovd/SWRoute/wiki/Function-hooking-in-Swift)? ⚡️
- Test against Swift Nightly as Cron Job
- Switch to Trampolines to manage cases where other code overrides super, so we end up with a super call that's [not on top of the class hierarchy](https://github.com/steipete/InterposeKit/pull/15#discussion_r439871752).
- I'm sure there's more - Pull Requests or [comments](https://twitter.com/steipete) very welcome!

Make this happen:
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
![CocoaPods](https://img.shields.io/cocoapods/v/SwiftyJSON.svg)

## Thanks

Special thanks to [JP Simard](https://github.com/jpsim/Yams) who did such a great job in setting up [Yams](https://github.com/jpsim/Yams) with GitHub Actions - this was extremely helpful to build CI here fast.

## License

InterposeKit is MIT Licensed.
