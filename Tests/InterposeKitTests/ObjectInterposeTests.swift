import Foundation
import XCTest
@testable import InterposeKit

final class ObjectInterposeTests: XCTestCase {

    override func setUpWithError() throws {
        Interpose.isLoggingEnabled = true
    }

    func testInterposeSingleObject() throws {
        let testObj = TestClass()
        let testObj2 = TestClass()

        XCTAssertEqual(testObj.sayHi(), testClassHi)
        XCTAssertEqual(testObj2.sayHi(), testClassHi)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(testObj) {
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
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
        XCTAssertEqual(testObj2.sayHi(), testClassHi)
        try interposer.revert()
        XCTAssertEqual(testObj.sayHi(), testClassHi)
        XCTAssertEqual(testObj2.sayHi(), testClassHi)
        try interposer.apply()
        XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
        XCTAssertEqual(testObj2.sayHi(), testClassHi)
    }

    func testInterposeSingleObjectInt() throws {
        let testObj = TestClass()
        let returnIntDefault = testObj.returnInt()
        let returnIntOverrideOffset = 2
        XCTAssertEqual(testObj.returnInt(), returnIntDefault)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(testObj) {
            try $0.hook(#selector(TestClass.returnInt), { store in { `self` in
                // Calling convention and passing selector is important!
                // You're free to skip calling the original implementation.
                let origCall = store((@convention(c) (AnyObject, Selector) -> Int).self)
                let int = origCall(`self`, store.selector)
                return int + returnIntOverrideOffset

                // Similar signature cast as above, but without selector.
                } as @convention(block) (AnyObject) -> Int})
        }
        XCTAssertEqual(testObj.returnInt(), returnIntDefault + returnIntOverrideOffset)
        try interposer.revert()
        XCTAssertEqual(testObj.returnInt(), returnIntDefault)
        try interposer.apply()
        // ensure we really don't leak into another object
        let testObj2 = TestClass()
        XCTAssertEqual(testObj2.returnInt(), returnIntDefault)
        XCTAssertEqual(testObj.returnInt(), returnIntDefault + returnIntOverrideOffset)
        try interposer.revert()
        XCTAssertEqual(testObj.returnInt(), returnIntDefault)
    }

    func testDoubleIntegerInterpose() throws {
        let testObj = TestClass()
        let returnIntDefault = testObj.returnInt()
        let returnIntOverrideOffset = 2
        let returnIntClassMultiplier = 4
        XCTAssertEqual(testObj.returnInt(), returnIntDefault)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(testObj) {
            try $0.hook(#selector(TestClass.returnInt), { store in { `self` in
                // Calling convention and passing selector is important!
                // You're free to skip calling the original implementation.
                let origCall = store((@convention(c) (AnyObject, Selector) -> Int).self)
                let int = origCall(`self`, store.selector)
                return int + returnIntOverrideOffset

                // Similar signature cast as above, but without selector.
                } as @convention(block) (AnyObject) -> Int})
        }
        XCTAssertEqual(testObj.returnInt(), returnIntDefault + returnIntOverrideOffset)

        // Interpose on TestClass itself!
        let classInterposer = try Interpose(TestClass.self) {
            try $0.hook(#selector(TestClass.returnInt), { store in { `self` in
                // Calling convention and passing selector is important!
                // You're free to skip calling the original implementation.
                let origCall = store((@convention(c) (AnyObject, Selector) -> Int).self)
                let int = origCall(`self`, store.selector)
                return int * returnIntClassMultiplier

                // Similar signature cast as above, but without selector.
                } as @convention(block) (AnyObject) -> Int})
        }

        XCTAssertEqual(testObj.returnInt(), (returnIntDefault * returnIntClassMultiplier) + returnIntOverrideOffset)

        // ensure we really don't leak into another object
        let testObj2 = TestClass()
        XCTAssertEqual(testObj2.returnInt(), returnIntDefault * returnIntClassMultiplier)

        try interposer.revert()
        XCTAssertEqual(testObj.returnInt(), returnIntDefault * returnIntClassMultiplier)
        try classInterposer.revert()
        XCTAssertEqual(testObj.returnInt(), returnIntDefault)
    }
}
