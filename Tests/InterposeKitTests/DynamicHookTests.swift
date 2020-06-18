import Foundation
import XCTest
@testable import InterposeKit

final class DynamicInterposeTests: InterposeKitTestCase {

    func testDynamicSingleObject() throws {
        let testObj = TestClass()

        // Test regular usage, calls block immediately
        var executed = false
        testObj.executeBlock {
            executed = true
        }
        XCTAssertTrue(executed)

        // Add hook that is called before the block
        var hookExecuted = false
        _ = try testObj.hook(#selector(TestClass.executeBlock)) { bSelf in
            print("Before Interposing Dynamic Hook for \(bSelf)")
            hookExecuted = true
        }

        // Ensure that hook is called before the block
        executed = false
        XCTAssertFalse(hookExecuted)
        testObj.executeBlock {
            // A before aspect is called before the block is executed
            XCTAssertTrue(hookExecuted)
        }
        XCTAssertTrue(hookExecuted)
    }
}
