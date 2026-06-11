#if !os(Linux)
import CoreFoundation
#endif
import Foundation

private final class InterposeObjectReferenceStorage {
    private let strongObject: AnyObject?
    private weak var weakObject: AnyObject?

    init(strong object: AnyObject) {
        strongObject = object
        weakObject = nil
    }

    init(weak object: AnyObject) {
        strongObject = nil
        weakObject = object
    }

    var object: AnyObject? {
        strongObject ?? weakObject
    }
}

extension NSObject {
    /// Hook an `@objc dynamic` instance method via selector  on the current object or class..
    @discardableResult public func hook<MethodSignature, HookSignature> (
        _ selector: Selector,
        methodSignature: MethodSignature.Type = MethodSignature.self,
        hookSignature: HookSignature.Type = HookSignature.self,
        _ implementation: (TypedHook<MethodSignature, HookSignature>) -> HookSignature?) throws -> AnyHook {

        if let klass = self as? AnyClass {
            return try Interpose.ClassHook(class: klass, selector: selector, implementation: implementation).apply()
        } else {
            return try Interpose.ObjectHook(object: self, selector: selector, implementation: implementation).apply()
        }
    }

    /// Hook an `@objc dynamic` instance method via selector  on the current object or class..
    @discardableResult public class func hook<MethodSignature, HookSignature> (
        _ selector: Selector,
        methodSignature: MethodSignature.Type = MethodSignature.self,
        hookSignature: HookSignature.Type = HookSignature.self,
        _ implementation: (TypedHook<MethodSignature, HookSignature>) -> HookSignature?) throws -> AnyHook {
        return try Interpose.ClassHook(class: self as AnyClass,
                                       selector: selector, implementation: implementation).apply()
    }
}

/// Interpose is a modern library to swizzle elegantly in Swift.
///
/// Methods are hooked via replacing the implementation, instead of the usual exchange.
/// Supports both swizzling classes and individual objects.
final public class Interpose {
    /// Controls whether an object-based interposer retains its target.
    public struct ObjectReference {
        private let storage: InterposeObjectReferenceStorage

        init(strong object: AnyObject) {
            storage = InterposeObjectReferenceStorage(strong: object)
        }

        init(weak object: AnyObject) {
            storage = InterposeObjectReferenceStorage(weak: object)
        }

        /// Creates a reference that retains the target object.
        public static func strong(_ object: NSObject) -> ObjectReference {
            ObjectReference(strong: object)
        }

        /// Creates a reference that allows the target object to deallocate.
        public static func weak(_ object: NSObject) -> ObjectReference {
            ObjectReference(weak: object)
        }

        /// The target object, or `nil` after a weakly referenced target deallocates.
        public var object: AnyObject? {
            storage.object
        }
    }

    /// Stores swizzle hooks and executes them at once.
    public let `class`: AnyClass
    /// Lists all hooks for the current interpose class object.
    public private(set) var hooks: [AnyHook] = []

    /// If Interposing is object-based, this is set.
    public var object: AnyObject? {
        objectReference?.object
    }

    private let objectReference: ObjectReference?

    // Checks if a object is posing as a different class
    // via implementing 'class' and returning something else.
    private static func checkObjectPosingAsDifferentClass(_ object: AnyObject) -> AnyClass? {
        let perceivedClass: AnyClass = type(of: object)
        let actualClass: AnyClass = object_getClass(object)!
        if actualClass != perceivedClass {
            return actualClass
        }
        return nil
    }

    // This is based on observation, there is no documented way
    private static func isKVORuntimeGeneratedClass(_ klass: AnyClass) -> Bool {
        String(cString: class_getName(klass)).contains("NSKVONotifying_")
    }

    #if !os(Linux)
    private static let objectiveCObjectTypeID = CFGetTypeID(NSObject())
    #endif

    private static func isCoreFoundationBackedObject(_ object: AnyObject) -> Bool {
        #if os(Linux)
        return false
        #else
        return CFGetTypeID(object as CFTypeRef) != objectiveCObjectTypeID
        #endif
    }

    static func validateObjectForHooking(_ object: AnyObject) throws {
        if let actualClass = checkObjectPosingAsDifferentClass(object) {
            if isKVORuntimeGeneratedClass(actualClass) {
                throw InterposeError.keyValueObservationDetected(object)
            } else if !InterposeSubclass.isInterposeSubclass(actualClass) {
                throw InterposeError.objectPosingAsDifferentClass(object, actualClass: actualClass)
            }
        }
        if isCoreFoundationBackedObject(object) {
            throw InterposeError.coreFoundationObjectDetected(object)
        }
    }

    /// Initializes an instance of Interpose for a specific class.
    /// If `builder` is present, `apply()` is automatically called.
    public init(_ `class`: AnyClass, builder: ((Interpose) throws -> Void)? = nil) throws {
        self.class = `class`
        self.objectReference = nil

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    /// Initialize with a single object to interpose.
    public convenience init(_ object: NSObject, builder: ((Interpose) throws -> Void)? = nil) throws {
        try self.init(.strong(object), builder: builder)
    }

    /// Initialize with a strong or weak reference to a single object.
    public init(_ objectReference: ObjectReference, builder: ((Interpose) throws -> Void)? = nil) throws {
        guard let object = objectReference.object else {
            throw InterposeError.objectDeallocated
        }

        self.objectReference = objectReference
        self.class = type(of: object)
        try Self.validateObjectForHooking(object)

        // Only apply if a builder is present
        if let builder = builder {
            try apply(builder)
        }
    }

    deinit {
        hooks.forEach({ $0.cleanup() })
    }

    /// Hook an `@objc dynamic` instance method via selector name on the current class.
    @discardableResult public func hook<MethodSignature, HookSignature>(
        _ selName: String,
        methodSignature: MethodSignature.Type = MethodSignature.self,
        hookSignature: HookSignature.Type = HookSignature.self,
        _ implementation: (TypedHook<MethodSignature, HookSignature>) -> HookSignature?)
        throws -> TypedHook<MethodSignature, HookSignature> {
        try hook(NSSelectorFromString(selName),
            methodSignature: methodSignature, hookSignature: hookSignature, implementation)
    }

    /// Hook an `@objc dynamic` instance method via selector  on the current class.
    @discardableResult public func hook<MethodSignature, HookSignature> (
        _ selector: Selector,
        methodSignature: MethodSignature.Type = MethodSignature.self,
        hookSignature: HookSignature.Type = HookSignature.self,
        _ implementation: (TypedHook<MethodSignature, HookSignature>) -> HookSignature?)
        throws -> TypedHook<MethodSignature, HookSignature> {
            let hook = try prepareHook(selector, methodSignature: methodSignature,
                                       hookSignature: hookSignature, implementation)
            try hook.apply()
            return hook

    }

    /// Prepares a hook, but does not call apply immediately.
    @discardableResult public func prepareHook<MethodSignature, HookSignature> (
        _ selector: Selector,
        methodSignature: MethodSignature.Type = MethodSignature.self,
        hookSignature: HookSignature.Type = HookSignature.self,
        _ implementation: (TypedHook<MethodSignature, HookSignature>) -> HookSignature?)
        throws -> TypedHook<MethodSignature, HookSignature> {
            var hook: TypedHook<MethodSignature, HookSignature>
            if let objectReference = self.objectReference {
                hook = try ObjectHook(
                    objectReference: objectReference, selector: selector, implementation: implementation)
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
                         expectedState: AnyHook.State = .prepared,
                         executor: ((AnyHook) throws -> Void)) throws -> Interpose {
        // Run pre-apply code first
        if let task = task {
            try task(self)
        }
        // Validate all tasks, stop if anything is not valid
        guard hooks.allSatisfy({
            (try? $0.validate(expectedState: expectedState)) != nil
        }) else {
            throw InterposeError.invalidState(expectedState: expectedState)
        }
        // Execute all tasks
        try hooks.forEach(executor)
        return self
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
