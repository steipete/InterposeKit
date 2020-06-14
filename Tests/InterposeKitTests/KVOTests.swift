import Foundation
import XCTest
@testable import InterposeKit

final class KVOTests: InterposeKitTestCase {

    // Helper observer that wraps a token and removes it on deinit.
    class TestClassObserver {
        var kvoToken: NSKeyValueObservation?
        var didCallObserver = false

        func observe(obj: TestClass) {
            kvoToken = obj.observe(\.age, options: .new) { [weak self] obj, change in
                guard let age = change.newValue else { return }
                print("New age is: \(age)")
                self?.didCallObserver = true
            }
        }

        deinit {
            kvoToken?.invalidate()
        }
    }


    func testBasicKVO() throws {
        let testObj = TestClass()

        // KVO before hooking works, but hooking will fail
        try withExtendedLifetime(TestClassObserver()) { observer in
            observer.observe(obj: testObj)
            XCTAssertEqual(testObj.age, 1)
            testObj.age = 2
            XCTAssertEqual(testObj.age, 2)
            // Hooking is expected to fail
            assert(try Interpose(testObj), throws: InterposeError.keyValueObservationDetected(testObj))
            XCTAssertEqual(testObj.age, 2)
        }

        // Hook without KVO!
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
        try interpose.revert()
        XCTAssertEqual(testObj.age, 2)
        try interpose.apply()
        XCTAssertEqual(testObj.age, 3)

        // Now we KVO after hooking!
        withExtendedLifetime(TestClassObserver()) { observer in
            observer.observe(obj: testObj)
            XCTAssertEqual(testObj.age, 3)
            // Setter is fine but won't change outcome
            XCTAssertFalse(observer.didCallObserver)
            testObj.age = 4
            XCTAssertTrue(observer.didCallObserver)
            XCTAssertEqual(testObj.age, 3)
        }
    }
}
