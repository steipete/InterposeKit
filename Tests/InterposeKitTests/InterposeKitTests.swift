import XCTest
@testable import InterposeKit

final class InterposeKitTests: XCTestCase {

    override func setUpWithError() throws {
        Interpose.isLoggingEnabled = true
    }

    func testClassOverrideAndRevert() throws {
        let testObj = TestClass()
        XCTAssertEqual(testObj.sayHi(), testClassHi)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(TestClass.self) {
            try $0.hook(#selector(TestClass.sayHi), { store in { `self` in

                print("Before Interposing \(`self`)")

                // Calling convention and passing selector is important!
                // You're free to skip calling the original implementation.
                let origCall = store((@convention(c) (AnyObject, Selector) -> String).self)
                let string = origCall(`self`, store.selector)

                print("After Interposing \(`self`)")

                return string + testSwizzleAddition

                // Similar signature cast as above, but without selector.
                } as @convention(block) (AnyObject) -> String})
        }

        print(TestClass().sayHi())

        // Test various apply/revert's
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
        try interposer.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi)
        try interposer.apply()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
        XCTAssertThrowsError(try interposer.apply())
        XCTAssertThrowsError(try interposer.apply())
        try interposer.revert()
        XCTAssertThrowsError(try interposer.revert())
        try interposer.apply()
        try interposer.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi)
    }

    func testSubclassOverride() throws {
        let testObj = TestSubclass()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass)

        // Swizzle test class
        let interposed = try Interpose(TestClass.self) {
            try $0.hook(#selector(TestClass.sayHi), { store in { `self` in
                let origCall = store((@convention(c) (AnyObject, Selector) -> String).self)
                return origCall(`self`, store.selector) + testSwizzleAddition
                } as @convention(block) (AnyObject) -> String})
        }

        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition + testSubclass)
        try interposed.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass)
        try interposed.apply()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition + testSubclass)

        // Swizzle subclass, automatically applys
        let interposedSubclass = try Interpose(TestSubclass.self) {
            try $0.hook(#selector(TestSubclass.sayHi), { store in { blockSelf in
                let origCall = store((@convention(c) (AnyObject, Selector) -> String).self)
                return origCall(blockSelf, store.selector) + testSwizzleAddition
                } as @convention(block) (AnyObject) -> String})
        }

        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition + testSubclass + testSwizzleAddition)
        try interposed.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass + testSwizzleAddition)
        try interposedSubclass.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass)
    }

    func testInterposedCleanup() throws {
        var deallocated = false

        try autoreleasepool {
            let tracker = LifetimeTracker {
                deallocated = true
            }

            // Swizzle test class
            let interposer = try Interpose(TestClass.self) {
                try $0.hook(#selector(TestClass.doNothing), { store in { `self` in
                    tracker.keep()
                    let origCall = store((@convention(c) (AnyObject, Selector) -> Void).self)
                    return origCall(`self`, store.selector)
                } as @convention(block) (AnyObject) -> Void })
            }

            // Dealloc interposer without removing hooks
            _ = interposer
        }

        // Unreverted block should not be deallocated
        XCTAssertFalse(deallocated)
    }

    func testRevertedCleanup() throws {
        var deallocated = false

        try autoreleasepool {
            let tracker = LifetimeTracker {
                deallocated = true
            }

            // Swizzle test class
            let interposer = try Interpose(TestClass.self) {
                try $0.hook(#selector(TestClass.doNothing), { store in { `self` in
                    tracker.keep()
                    let origCall = store((@convention(c) (AnyObject, Selector) -> Void).self)
                    return origCall(`self`, store.selector)
                } as @convention(block) (AnyObject) -> Void })
            }

            try interposer.revert()
        }

        // Verify that the block was deallocated
        XCTAssertTrue(deallocated)
    }

    func testImpRemoveBlockWorks() {
        var deallocated = false

        let imp: IMP = autoreleasepool {
            let tracker = LifetimeTracker {
                deallocated = true
            }

            let block: @convention(block) (AnyObject) -> Void = { _ in
                // retain `tracker` inside a block
                tracker.keep()
            }

            return imp_implementationWithBlock(block)
        }

        // `imp` retains `block` which retains `tracker`
        XCTAssertFalse(deallocated)

        // Detach `block` from `imp`
        imp_removeBlock(imp)

        // `block` and `tracker` should be deallocated now
        XCTAssertTrue(deallocated)
    }

    class LifetimeTracker {
        let deinitCalled: () -> Void

        init(deinitCalled: @escaping () -> Void) {
            self.deinitCalled = deinitCalled
        }

        deinit {
            deinitCalled()
        }

        func keep() { }
    }

    static var allTests = [
        ("testClassOverrideAndRevert", testClassOverrideAndRevert),
        ("testSubclassOverride", testSubclassOverride),
        ("testInterposedCleanup", testInterposedCleanup),
        ("testRevertedCleanup", testRevertedCleanup),
        ("testImpRemoveBlockWorks", testImpRemoveBlockWorks)
    ]
}
