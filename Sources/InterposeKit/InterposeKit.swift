import Foundation

/// Helper to swizzle methods the right way, via replacing the IMP.
final public class Interpose {
    /// Stores swizzle hooks and executes them at once.
    public let `class`: AnyClass
    /// Lists all hooks for the current interpose class object.
    public private(set) var hooks: [Hookable] = []

    /// If Interposing is object-based, this is set.
    public let object: AnyObject?

    /// Initializes an instance of Interpose for a specific class.
    /// If `builder` is present, `apply()` is automatically called.
    public init(_ `class`: AnyClass, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.class = `class`
        self.object = nil

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    /// Initialize with a single object to interpose.
    public init(_ object: AnyObject, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.object = object
        self.class = type(of: object)

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    deinit {
        guard let internalHooks = hooks as? [InternalHookable] else { return }
        internalHooks.forEach({ $0.cleanup() })
    }

    /// Hook an `@objc dynamic` instance method via selector name on the current class.
    @discardableResult public func hook(_ selName: String,
                                        _ implementation: (Hookable) -> Any) throws -> Hookable {
        try hook(NSSelectorFromString(selName), implementation)
    }

    /// Hook an `@objc dynamic` instance method via selector  on the current class.
    @discardableResult public func hook(_ selector: Selector,
                                        _ implementation: (Hookable) -> Any) throws -> Hookable {

        var hook: InternalHookable
        if let object = self.object {
            hook = try ObjectHook(object: object, selector: selector, implementation: implementation)
        } else {
            hook = try ClassHook(class: `class`, selector: selector, implementation: implementation)
        }
        hooks.append(hook)
        return hook
    }

    /// Apply all stored hooks.
    @discardableResult public func apply(_ hook: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(hook) { try $0.apply() }
    }

    /// Revert all stored hooks.
    @discardableResult public func revert(_ hook: ((Interpose) throws -> Void)? = nil) throws -> Interpose {
        try execute(hook, expectedState: .interposed) { try $0.revert() }
    }

    private func execute(_ task: ((Interpose) throws -> Void)? = nil,
                         expectedState: Interpose.State = .prepared,
                         executor: ((Hookable) throws -> Void)) throws -> Interpose {
        // Run pre-apply code first
        if let task = task {
            try task(self)
        }
        // Validate all tasks, stop if anything is not valid
        guard let internalHooks = hooks as? [InternalHookable], internalHooks.allSatisfy({
            (try? $0.validate(expectedState: expectedState)) != nil
        }) else {
            throw Error.invalidState
        }
        // Execute all tasks
        try hooks.forEach(executor)
        return self
    }

    /// The list of errors while hooking a method.
    public enum Error: Swift.Error {
        /// The method couldn't be found. Usually happens for when you use stringified selectors that do not exist.
        case methodNotFound

        /// The implementation could not be found. Class must be in a weird state for this to happen.
        case nonExistingImplementation

        /// Someone else changed the implementation; reverting removed this implementation.
        /// This is bad, likely someone else also hooked this method. If you are in such a codebase, do not use revert.
        case unexpectedImplementation

        case failedToAllocateClassPair

        /// Can't revert or apply if already done so.
        case invalidState
    }

    /// The possible task states.
    public enum State: Equatable {
        /// The task is prepared to be interposed.
        case prepared

        /// The method has been successfully interposed.
        case interposed

        /// An error happened while interposing a method.
        case error(Interpose.Error)
    }
}

// MARK: Logging

extension Interpose {
    /// Logging uses print and is minimal.
    public static var isLoggingEnabled = false

    /// Simple log wrapper for print.
    class func log(_ object: Any) {
        if isLoggingEnabled {
            print("[Interposer] \(object)")
        }
    }
}
