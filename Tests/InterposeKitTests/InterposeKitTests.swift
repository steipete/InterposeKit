import XCTest
@testable import InterposeKit

let testClassHi = "Hi from TestClass!"
let testSwizzleAddition = " and Interpose"
let testSubclass = "Subclass is here!"

class TestClass: NSObject {
    @objc dynamic func sayHi() -> String {
        print(testClassHi)
        return testClassHi
    }
}

class TestSubclass: TestClass {
    override func sayHi() -> String {
        return super.sayHi() + testSubclass
    }
}

final class InterposeKitTests: XCTestCase {

    func testClassOverrideAndRevert() throws {
        let testObj = TestClass()
        XCTAssertEqual(testObj.sayHi(), testClassHi)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(TestClass.self) {
            try $0.hook(#selector(TestClass.sayHi), { store in { `self` in

                print("Before Interposing \(`self`)")

                // Calling convention and passing selector is important!
                // You're free to skip calling the original implementation.
                let string = store((@convention(c) (AnyObject, Selector) -> String).self)(`self`, store.selector)

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

    static var allTests = [
        ("testClassOverrideAndRevert", testClassOverrideAndRevert),
        ("testSubclassOverride", testSubclassOverride)
    ]
}
