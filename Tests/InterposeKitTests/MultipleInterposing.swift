import Foundation
import XCTest
@testable import InterposeKit

func testInterposeSingleObjectMultipleTimes() throws {
    let testObj = TestClass()
    let testObj2 = TestClass()

    XCTAssertEqual(testObj.sayHi(), testClassHi)
    XCTAssertEqual(testObj2.sayHi(), testClassHi)

    // Functions need to be `@objc dynamic` to be hookable.
    let interposer = try Interpose(testObj) {
        try $0.hook(
            #selector(TestClass.sayHi),
            methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
            hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { `self` in
                return store.original(`self`, store.selector) + testSwizzleAddition
                }
        }
    }

    XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
    XCTAssertEqual(testObj2.sayHi(), testClassHi)

    let interposer2 = try Interpose(testObj) {
        try $0.hook(
            #selector(TestClass.sayHi),
            methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
            hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { `self` in
                return store.original(`self`, store.selector) + testSwizzleAddition
                }
        }
    }

    // TODO: detect existing hook?

    XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)


    try interposer.revert()
    try interposer2.revert()
//    XCTAssertEqual(testObj.sayHi(), testClassHi)
//    XCTAssertEqual(testObj2.sayHi(), testClassHi)
//    try interposer.apply()
//    XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
//    XCTAssertEqual(testObj2.sayHi(), testClassHi)
}
