import Foundation

/// The list of errors while hooking a method.
public enum InterposeError: LocalizedError {
    /// The method couldn't be found. Usually happens for when you use stringified selectors that do not exist.
    case methodNotFound(AnyClass, Selector)

    /// The implementation could not be found. Class must be in a weird state for this to happen.
    case nonExistingImplementation(AnyClass, Selector)

    /// Someone else changed the implementation; reverting removed this implementation.
    /// This is bad, likely someone else also hooked this method. If you are in such a codebase, do not use revert.
    case unexpectedImplementation(AnyClass, Selector, IMP?)

    /// Unable to register subclass for object-based interposing.
    case failedToAllocateClassPair(class: AnyClass, subclassName: String)

    /// Unable to add method  for object-based interposing.
    case unableToAddMethod(AnyClass, Selector)

    /// Object-based hooking does not work if an object is using KVO.
    /// The KVO mechanism also uses subclasses created at runtime but doesn't check for additional overrides.
    /// Adding a hook eventually crashes the KVO management code so we reject hooking altogether in this case.
    case keyValueObservationDetected(AnyObject)

    /// Object is lying about it's actual class metadata.
    /// This usually happens when other swizzling libraries (like Aspects) also interfere with a class.
    /// While this might just work, it's not worth risking a crash, so similar to KVO this case is rejected.
    ///
    /// @note Printing classes in Swift uses the class posing mechanism.
    /// Use `NSClassFromString` to get the correct name.
    case objectPosingAsDifferentClass(AnyObject, actualClass: AnyClass)

    /// Can't revert or apply if already done so.
    case invalidState(expectedState: AnyHook.State)

    /// Unable to remove hook.
    case resetUnsupported(_ reason: String)

    /// Generic failure
    case unknownError(_ reason: String)
}

extension InterposeError: Equatable {
    // Lazy equating via string compare
    public static func == (lhs: InterposeError, rhs: InterposeError) -> Bool {
        return lhs.errorDescription == rhs.errorDescription
    }

    public var errorDescription: String? {
        switch self {
        case .methodNotFound(let klass, let selector):
            return "Method not found: -[\(klass) \(selector)]"
        case .nonExistingImplementation(let klass, let selector):
            return "Implementation not found: -[\(klass) \(selector)]"
        case .unexpectedImplementation(let klass, let selector, let IMP):
            return "Unexpected Implementation in -[\(klass) \(selector)]: \(String(describing: IMP))"
        case .failedToAllocateClassPair(let klass, let subclassName):
            return "Failed to allocate class pair: \(klass), \(subclassName)"
        case .unableToAddMethod(let klass, let selector):
            return "Unable to add method: -[\(klass) \(selector)]"
        case .keyValueObservationDetected(let obj):
            return "Unable to hook object that uses Key Value Observing: \(obj)"
        case .objectPosingAsDifferentClass(let obj, let actualClass):
            return "Unable to hook \(type(of: obj)) posing as \(NSStringFromClass(actualClass))/"
        case .invalidState(let expectedState):
            return "Invalid State. Expected: \(expectedState)"
        case .resetUnsupported(let reason):
            return "Reset Unsupported: \(reason)"
        case .unknownError(let reason):
            return reason
        }
    }

    @discardableResult func log() -> InterposeError {
        Interpose.log(self.errorDescription!)
        return self
    }
}
