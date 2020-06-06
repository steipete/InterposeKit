import Foundation

/// A task represents a hook to an instance method and stores both the original and new implementation.
final public class ClassTask: ValidatableTask {
    public let `class`: AnyClass
    public let selector: Selector
    public private(set) var origIMP: IMP? // fetched at apply time, changes late, thus class requirement
    public private(set) var replacementIMP: IMP! // else we validate init order
    public private(set) var state = Interpose.State.prepared

    /// Initialize a new task to interpose an instance method.
    public init(`class`: AnyClass, selector: Selector, implementation: (Task) -> Any) throws {
        self.selector = selector
        self.class = `class`
        // Check if method exists
        try validate()
        replacementIMP = imp_implementationWithBlock(implementation(self))
    }

    /// Validate that the selector exists on the active class.
    @discardableResult public func validate(expectedState: Interpose.State = .prepared) throws -> Method {
        guard let method = class_getInstanceMethod(`class`, selector) else { throw Interpose.Error.methodNotFound }
        guard state == expectedState else { throw Interpose.Error.invalidState }
        return method
    }

    public func apply() throws {
        try execute(newState: .interposed) { try replaceImplementation() }
    }

    public func revert() throws {
        try execute(newState: .prepared) { try resetImplementation() }
    }

    /// Release the hook block if possible.
    public func cleanup() {
        switch state {
        case .prepared:
            Interpose.log("Releasing -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
            imp_removeBlock(replacementIMP)
        case .interposed:
            Interpose.log("Keeping -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
        case let .error(error):
            Interpose.log("Leaking -[\(`class`).\(selector)] IMP: \(replacementIMP!) due to error: \(error)")
        }
    }

    private func execute(newState: Interpose.State, task: () throws -> Void) throws {
        do {
            try task()
            state = newState
        } catch let error as Interpose.Error {
            state = .error(error)
            throw error
        }
    }

    private func replaceImplementation() throws {
        let method = try validate()
        origIMP = class_replaceMethod(`class`, selector, replacementIMP, method_getTypeEncoding(method))
        guard origIMP != nil else { throw Interpose.Error.nonExistingImplementation }
        Interpose.log("Swizzled -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
    }

    private func resetImplementation() throws {
        let method = try validate(expectedState: .interposed)
        precondition(origIMP != nil)
        let previousIMP = class_replaceMethod(`class`, selector, origIMP!, method_getTypeEncoding(method))
        guard previousIMP == replacementIMP else { throw Interpose.Error.unexpectedImplementation }
        Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
    }

    public func callAsFunction<U>(_ type: U.Type) -> U {
        unsafeBitCast(origIMP, to: type)
    }
}

#if DEBUG
extension ClassTask: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) -> \(String(describing: origIMP))"
    }
}
#endif
