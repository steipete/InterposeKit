import XCTest
@testable import InterposeKit

class InterposeKitTestCase: XCTestCase {
    override func setUpWithError() throws {
        Interpose.isLoggingEnabled = true
    }
}

extension InterposeKitTestCase {
    // https://www.swiftbysundell.com/articles/testing-error-code-paths-in-swift/
    func assert<T, E: Error & Equatable>(
        _ expression: @autoclosure () throws -> T,
        throws error: E,
        in file: StaticString = #file,
        line: UInt = #line
    ) {
        var thrownError: Error?

        XCTAssertThrowsError(try expression(),
                             file: file, line: line) {
                                thrownError = $0
        }

        XCTAssertTrue(
            thrownError is E,
            "Unexpected error type: \(type(of: thrownError))",
            file: file, line: line
        )

        XCTAssertEqual(
            thrownError as? E, error,
            file: file, line: line
        )
    }
}
