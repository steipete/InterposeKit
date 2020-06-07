import Foundation

public protocol Hookable: class {
    /// The class this hook operates on.
    var `class`: AnyClass { get }

    /// If Interposing is object-based, this is set.
    //var object: AnyObject? { get }

    /// The selector this hook operates on.
    var selector: Selector { get }

    /// The original implementation is set once the swizzling is complete.
    var origIMP: IMP? { get }

    /// The replacement implementation is created on initialization time.
    var replacementIMP: IMP! { get }

    /// The state of the interpose operation.
    var state: Interpose.State { get }

    /// Apply the interpose hook.
    func apply() throws

    /// Revert the interpose hoook.
    func revert() throws

    /// Convenience to call the original implementation.
    func callAsFunction<U>(_ type: U.Type) -> U
}

extension Hookable {
    public func callAsFunction<U>(_ type: U.Type) -> U {
        unsafeBitCast(origIMP, to: type)
    }

    /// Validate that the selector exists on the active class.
    @discardableResult func validate(expectedState: Interpose.State = .prepared) throws -> Method {
        guard let method = class_getInstanceMethod(`class`, selector) else { throw Interpose.Error.methodNotFound }
        guard state == expectedState else { throw Interpose.Error.invalidState }
        return method
    }
}

public protocol InternalHookable: Hookable {
    var state: Interpose.State { get set }

    func replaceImplementation() throws

    func resetImplementation() throws

    func cleanup()
}

extension InternalHookable {
    func apply() throws {
        try execute(newState: .interposed) { try replaceImplementation() }
    }

    func revert() throws {
        try execute(newState: .prepared) { try resetImplementation() }
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
}
