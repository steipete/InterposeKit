import XCTest
@testable import InterposeKit

final class InterposeKitTests: InterposeKitTestCase {

    override func setUpWithError() throws {
        Interpose.isLoggingEnabled = true
    }

    func testClassOverrideAndRevert() throws {
        let testObj = TestClass()
        XCTAssertEqual(testObj.sayHi(), testClassHi)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(TestClass.self).hook(
            #selector(TestClass.sayHi),
            methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
            hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { bSelf in
                // You're free to skip calling the original implementation.
                print("Before Interposing \(bSelf)")
                let string = store.original(bSelf, store.selector)
                print("After Interposing \(bSelf)")

                return string + testString
                }
        }

        print(TestClass().sayHi())

        // Test various apply/revert's
        XCTAssertEqual(testObj.sayHi(), testClassHi + testString)
        try interposer.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi)
        try interposer.apply()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testString)
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
            try $0.hook(
                #selector(TestClass.sayHi),
                methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
                hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { bSelf in
                    return store.original(bSelf, store.selector) + testString
                    }
            }
        }

        XCTAssertEqual(testObj.sayHi(), testClassHi + testString + testSubclass)
        try interposed.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass)
        try interposed.apply()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testString + testSubclass)

        // Swizzle subclass, automatically applys
        let interposedSubclass = try Interpose(TestSubclass.self).hook(
            #selector(TestSubclass.sayHi),
            methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
            hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { bSelf in
                return store.original(bSelf, store.selector) + testString
                }
        }

        XCTAssertEqual(testObj.sayHi(), testClassHi + testString + testSubclass + testString)
        try interposed.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSubclass + testString)
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
            let interposer = try Interpose(TestClass.self).hook(
                #selector(TestClass.doNothing),
                methodSignature: (@convention(c) (AnyObject, Selector) -> Void).self,
                hookSignature: (@convention(block) (AnyObject) -> Void).self) { store in { bSelf in
                    tracker.keep()
                    return store.original(bSelf, store.selector)
                    }
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
            let interposer = try Interpose(TestClass.self).hook(
                #selector(TestClass.doNothing),
                methodSignature: (@convention(c) (AnyObject, Selector) -> Void).self,
                hookSignature: (@convention(block) (AnyObject) -> Void).self) { store in { bSelf in
                    tracker.keep()
                    return store.original(bSelf, store.selector)
                    }
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
