import Foundation

private enum Constants {
    static let subclassSuffix = "InterposeKit_"
}

internal enum ObjCSelector {
    static let getClass = Selector((("class")))
}

internal enum ObjCMethodEncoding {
    static let getClass = extract("#@:")

    private static func extract(_ string: StaticString) -> UnsafePointer<CChar> {
        return UnsafeRawPointer(string.utf8Start).assumingMemoryBound(to: CChar.self)
    }
}

/// A task represents a hook to an instance method of a single object and stores both the original and new implementation.
final public class ObjectTask: ValidatableTask {
    public let `class`: AnyClass
    public let object: AnyObject
    public let selector: Selector
    public private(set) var origIMP: IMP? // fetched at apply time, changes late, thus class requirement
    public private(set) var replacementIMP: IMP! // else we validate init order
    public private(set) var state = Interpose.State.prepared

    // Subclass that we create on the fly
    var dynamicSubclass: AnyClass?

    /// Initialize a new task to interpose an instance method.
    public init(object: AnyObject, selector: Selector, implementation: (Task) -> Any) throws {
        self.selector = selector
        self.object = object
        self.class = type(of: object)
        // Check if method exists
        try validate()
        replacementIMP = imp_implementationWithBlock(implementation(self))
    }

    class KVOObserver: NSObject {
        @objc var objectToObserve: AnyObject
        var observation: NSKeyValueObservation?

        init(object: AnyObject) {
            objectToObserve = object
            super.init()

            // Can't use modern syntax cause https://bugs.swift.org/browse/SR-12944
            objectToObserve.addObserver(self, forKeyPath: "description", options: .new, context: nil)
        }
    }

    // Before creating our subclass, we trigger KVO.
    // KVO also creates a subclass at runtime. If we do this prior, then KVO fails.
    // If KVO runs prior, and then we sub-subclass, everything works.
    var kvoObserver: KVOObserver?
    private func registerKVO() {
        kvoObserver = KVOObserver(object: object)
    }

    private func createSubclass() throws -> AnyClass {
        let perceivedClass: AnyClass = `class`
        let className = NSStringFromClass(perceivedClass)
        // Right now we are wasteful. Might be able to optimize for shared IMP?
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let subclassName = Constants.subclassSuffix + className + uuid

        let subclass: AnyClass? = subclassName.withCString { cString in
            // swiftlint:disable:next force_cast
            if let existingClass = objc_getClass(cString) as! AnyClass? {
                return existingClass
            } else {
                if let subclass: AnyClass = objc_allocateClassPair(perceivedClass, cString, 0) {
                    replaceGetClass(in: subclass, decoy: perceivedClass)
                    objc_registerClassPair(subclass)
                    return subclass
                } else {
                    return nil
                }
            }
        }

        guard let nonnullSubclass = subclass else {
            throw Interpose.Error.failedToAllocateClassPair
        }

        object_setClass(object, nonnullSubclass)
        return nonnullSubclass
    }

    private func replaceGetClass(in class: AnyClass, decoy perceivedClass: AnyClass) {
        let getClass: @convention(block) (UnsafeRawPointer?) -> AnyClass = { _ in
            perceivedClass
        }
        let impl = imp_implementationWithBlock(getClass as Any)
        _ = class_replaceMethod(`class`, ObjCSelector.getClass, impl, ObjCMethodEncoding.getClass)
        _ = class_replaceMethod(object_getClass(`class`), ObjCSelector.getClass, impl, ObjCMethodEncoding.getClass)
    }

    // https://bugs.swift.org/browse/SR-12945
    struct objcSuperFake {
        public var receiver: Unmanaged<AnyObject>
        public var superClass: AnyClass
    }

    typealias MsgSendSuperType =  @convention(c) (UnsafePointer<objc_super>, Selector, va_list) -> Unmanaged<AnyObject>
    private lazy var msgSendSuper2 : MsgSendSuperType = {
        let handle = dlopen(nil, RTLD_LAZY)
        // https://opensource.apple.com/source/objc4/objc4-493.9/runtime/objc-abi.h
        // objc_msgSendSuper2() takes the current search class, not its superclass.
        // OBJC_EXPORT id objc_msgSendSuper2(struct objc_super *super, SEL op, ...)
        // TODO: This should be cached.
        let sendSuper2 = dlsym(handle, "objc_msgSendSuper2")
        return unsafeBitCast(sendSuper2, to: MsgSendSuperType.self)
    }()

    private func addSuperTrampolineMethod(subclass: AnyClass, method: Method) {
        let typeEncoding = method_getTypeEncoding(method)

        let block: @convention(block) (AnyObject, va_list) -> Unmanaged<AnyObject> = { obj, vaList in
            // This is an extremely cursed workaround for following crashing the compiler:
            // let realSuperStruct = objc_super(receiver: raw, super_class: subclass)
            // https://bugs.swift.org/browse/SR-12945
            let raw = Unmanaged<AnyObject>.passUnretained(obj)
            let superStruct = objcSuperFake(receiver: raw, superClass: subclass)
            let realSuperStruct = unsafeBitCast(superStruct, to: objc_super.self)
            // C: return ((id(*)(struct objc_super *, SEL, va_list))objc_msgSendSuper2)(&super, selector, argp);
            return withUnsafePointer(to: realSuperStruct) { realSuperStructPointer -> Unmanaged<AnyObject> in
                return self.msgSendSuper2(realSuperStructPointer, self.selector, vaList)
            }
        }
        class_addMethod(subclass, self.selector, imp_implementationWithBlock(block), typeEncoding)
    }
    
    /// Validate that the selector exists on the active class.
    @discardableResult public func validate(expectedState: Interpose.State = .prepared) throws -> Method {
        // We need to validate on class, not the subclass
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

        // Register a KVO to work around any KVO issues with opposite order
        registerKVO()

        // Register subclass at runtime if we haven't already
        if dynamicSubclass == nil {
            dynamicSubclass = try createSubclass()
        }
        // Add empty trampoline that we then replace the IMP!
        addSuperTrampolineMethod(subclass: dynamicSubclass!, method: method)

        origIMP = class_replaceMethod(dynamicSubclass!, selector, replacementIMP, method_getTypeEncoding(method))
        guard origIMP != nil else { throw Interpose.Error.nonExistingImplementation }
        Interpose.log("Swizzled -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
    }

    private func resetImplementation() throws {
        let method = try validate(expectedState: .interposed)
        precondition(origIMP != nil)
        precondition(dynamicSubclass != nil)

        let previousIMP = class_replaceMethod(dynamicSubclass!, selector, origIMP!, method_getTypeEncoding(method))
        guard previousIMP == replacementIMP else { throw Interpose.Error.unexpectedImplementation }
        Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
    }

    public func callAsFunction<U>(_ type: U.Type) -> U {
        unsafeBitCast(origIMP, to: type)
    }
}

#if DEBUG
extension ObjectTask: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) -> \(String(describing: origIMP))"
    }
}
#endif
