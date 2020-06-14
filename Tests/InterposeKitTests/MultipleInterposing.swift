import Foundation
import XCTest
@testable import InterposeKit

final class MultipleInterposingTests: InterposeKitTestCase {

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
                    return store.original(`self`, store.selector) + testString
                    }
            }
        }

        XCTAssertEqual(testObj.sayHi(), testClassHi + testString)
        XCTAssertEqual(testObj2.sayHi(), testClassHi)

        let interposer2 = try testObj.interpose?.hook(
            #selector(TestClass.sayHi),
            methodSignature: (@convention(c) (AnyObject, Selector) -> String).self,
            hookSignature: (@convention(block) (AnyObject) -> String).self) { store in { `self` in
                return store.original(`self`, store.selector) + testString2
                }
        }

        // TODO: detect existing hook?

        XCTAssertEqual(testObj.sayHi(), testClassHi + testString)


       // try interposer.revert()
        //try interposer2.revert()
        //    XCTAssertEqual(testObj.sayHi(), testClassHi)
        //    XCTAssertEqual(testObj2.sayHi(), testClassHi)
        //    try interposer.apply()
        //    XCTAssertEqual(testObj.sayHi(), testClassHi + testSwizzleAddition)
        //    XCTAssertEqual(testObj2.sayHi(), testClassHi)
    }

    func testInterposeAgeAndRevert() throws {
        let testObj = TestClass()
        XCTAssertEqual(testObj.age, 1)

        let interpose = try Interpose(testObj) {
            try $0.hook(#selector(getter: TestClass.age),
                        methodSignature: (@convention(c) (AnyObject, Selector) -> Int).self,
                        hookSignature: (@convention(block) (AnyObject) -> Int).self) {
                            store in { `self` in
                                return 3
                            }
            }
        }
        XCTAssertEqual(testObj.age, 3)

        try interpose.hook(#selector(getter: TestClass.age),
                    methodSignature: (@convention(c) (AnyObject, Selector) -> Int).self,
                    hookSignature: (@convention(block) (AnyObject) -> Int).self) {
                        store in { `self` in
                            return 5
                        }
        }.apply()
        XCTAssertEqual(testObj.age, 5)
        try interpose.revert()
        XCTAssertEqual(testObj.age, 1)
    }
}
