import Foundation

public class AnyHook {
    public let `class`: AnyClass
    public let selector: Selector
    public internal(set) var state = State.prepared

    // else we validate init order
    public internal(set) var replacementIMP: IMP!

    // fetched at apply time, changes late, thus class requirement
    public internal(set) var origIMP: IMP?
    
    /// The possible task states
    public enum State: Equatable {
        /// The task is prepared to be nterposed.
        case prepared
        
        /// The method has been successfully interposed.
        case interposed
        
        /// An error happened while interposing a method.
        indirect case error(InterposeError)
    }
    
    init(`class`: AnyClass, selector: Selector) throws {
        self.selector = selector
        self.class = `class`

        // Check if method exists
        try validate()
    }
    
    func replaceImplementation() throws {
        preconditionFailure("Not implemented")
    }
    
    func resetImplementation() throws {
        preconditionFailure("Not implemented")
    }
    
    /// Apply the interpose hook.
    public func apply() throws {
        try execute(newState: .interposed) { try replaceImplementation() }
    }
    
    /// Revert the interpose hoook.
    public func revert() throws {
        try execute(newState: .prepared) { try resetImplementation() }
    }

    public func callAsFunction<U>(_ type: U.Type) -> U {
        unsafeBitCast(origIMP, to: type)
    }
    
    /// Validate that the selector exists on the active class.
    @discardableResult func validate(expectedState: State = .prepared) throws -> Method {
        guard let method = class_getInstanceMethod(`class`, selector) else { throw InterposeError.methodNotFound(`class`, selector)}
        guard state == expectedState else { throw InterposeError.invalidState(expectedState: expectedState) }
        return method
    }
    
    private func execute(newState: State, task: () throws -> Void) throws {
        do {
            try task()
            state = newState
        } catch let error as InterposeError {
            state = .error(error)
            throw error
        }
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

    /// Internal: Restores the previous implementation if one is set.
    func restorePreviousIMP(exactClass: AnyClass) throws {
        let method = try validate(expectedState: .interposed)
        precondition(origIMP != nil)
        let previousIMP = class_replaceMethod(exactClass, selector, origIMP!, method_getTypeEncoding(method))
        guard previousIMP == replacementIMP else { throw InterposeError.unexpectedImplementation(exactClass, selector, previousIMP) }
        Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
    }
}

public class TypedHook<MethodSignature, HookSignature>: AnyHook {
    public var original: MethodSignature {
        preconditionFailure("Always override")
    }
}
