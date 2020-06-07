import Foundation

/// A hook to an instance method and stores both the original and new implementation.
final class ClassHook: InternalHookable {
    public let `class`: AnyClass
    public let selector: Selector
    public internal(set) var origIMP: IMP? // fetched at apply time, changes late, thus class requirement
    public private(set) var replacementIMP: IMP! // else we validate init order
    public internal(set) var state = Interpose.State.prepared

    /// Initialize a new hook to interpose an instance method.
    init(`class`: AnyClass, selector: Selector, implementation: (Hookable) -> Any) throws {
        self.selector = selector
        self.class = `class`
        // Check if method exists
        try validate()
        replacementIMP = imp_implementationWithBlock(implementation(self))
    }

    func replaceImplementation() throws {
        let method = try validate()
        origIMP = class_replaceMethod(`class`, selector, replacementIMP, method_getTypeEncoding(method))
        guard origIMP != nil else { throw Interpose.Error.nonExistingImplementation }
        Interpose.log("Swizzled -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
    }

    func resetImplementation() throws {
        let method = try validate(expectedState: .interposed)
        precondition(origIMP != nil)
        let previousIMP = class_replaceMethod(`class`, selector, origIMP!, method_getTypeEncoding(method))
        guard previousIMP == replacementIMP else { throw Interpose.Error.unexpectedImplementation }
        Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
    }
}

#if DEBUG
extension ClassHook: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) -> \(String(describing: origIMP))"
    }
}
#endif
