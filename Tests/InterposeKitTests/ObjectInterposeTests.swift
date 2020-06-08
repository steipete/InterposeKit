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
            try $0.hook(
                #selector(TestClass.sayHi),
                methodSignature: (@convention(c) (AnyObject, Selector) -> String).self) { store in { `self` in

                    print("Before Interposing \(`self`)")

                    // Calling convention and passing selector is important!
                    // You're free to skip calling the original implementation.
                    let string = store.original(`self`, store.selector)

                    print("After Interposing \(`self`)")

                    return string + testSwizzleAddition

                    // Similar signature cast as above, but without selector.
                    } as @convention(block) (AnyObject) -> String }
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
            try $0.hook(#selector(TestClass.returnInt)) { (store: TypedHook<@convention(c) (AnyObject, Selector) -> Int, @convention(block) (AnyObject) -> Int>) in {

                // You're free to skip calling the original implementation.
                let int = store.original($0, store.selector)
                return int + returnIntOverrideOffset
                }
            }
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
            try $0.hook(#selector(TestClass.returnInt)) { (store: TypedHook<@convention(c) (AnyObject, Selector) -> Int, @convention(block) (AnyObject) -> Int>) in {
                // You're free to skip calling the original implementation.
                store.original($0, store.selector) + returnIntOverrideOffset
                }
            }
        }
        XCTAssertEqual(testObj.returnInt(), returnIntDefault + returnIntOverrideOffset)

        // Interpose on TestClass itself!
        let classInterposer = try Interpose(TestClass.self) {
            try $0.hook(#selector(TestClass.returnInt)) { (store: TypedHook<@convention(c) (AnyObject, Selector) -> Int, @convention(block) (AnyObject) -> Int>) in {
                store.original($0, store.selector) * returnIntClassMultiplier
                }
            }
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

    func test3IntParameters() throws {
        let testObj = TestClass()
        XCTAssertEqual(testObj.calculate(var1: 1, var2: 2, var3: 3), 1 + 2 + 3)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(testObj) {
            try $0.hook(#selector(TestClass.calculate)) { (store: TypedHook<@convention(c) (AnyObject, Selector, Int, Int, Int) -> Int, @convention(block) (AnyObject, Int, Int, Int) -> Int>) in {
                // You're free to skip calling the original implementation.
                let orig = store.original($0, store.selector, $1, $2, $3)
                return orig + 1
                }
            }
        }
        XCTAssertEqual(testObj.calculate(var1: 1, var2: 2, var3: 3), 1 + 2 + 3 + 1)
        try interposer.revert()
    }

    func test6IntParameters() throws {
        let testObj = TestClass()

        XCTAssertEqual(testObj.calculate2(var1: 1, var2: 2, var3: 3, var4: 4, var5: 5, var6: 6), 1 + 2 + 3 + 4 + 5 + 6)

        // Functions need to be `@objc dynamic` to be hookable.
        let interposer = try Interpose(testObj) {
            try $0.hook(#selector(TestClass.calculate2)) { (store: TypedHook<@convention(c) (AnyObject, Selector, Int, Int, Int, Int, Int, Int) -> Int, @convention(block) (AnyObject, Int, Int, Int, Int, Int, Int) -> Int>) in {
                // You're free to skip calling the original implementation.
                let orig = store.original($0, store.selector, $1, $2, $3, $4, $5, $6)
                return orig + 1
                }
            }
        }
        XCTAssertEqual(testObj.calculate2(var1: 1, var2: 2, var3: 3, var4: 4, var5: 5, var6: 6),  1 + 2 + 3 + 4 + 5 + 6 + 1)
        try interposer.revert()
    }
}
