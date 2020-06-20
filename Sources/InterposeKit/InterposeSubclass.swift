import Foundation

class InterposeSubclass: ModifyableClass {

    private enum Constants {
        static let subclassSuffix = "InterposeKit_"
    }

    enum ObjCSelector {
        static let getClass = Selector((("class")))
        static let forwardInvocation = Selector((("forwardInvocation:")))
        //static let methodSignatureForSelector = Selector((("methodSignatureForSelector:")))
    }

    enum ObjCMethodEncoding {
        static let getClass = extract("#@:")
        static let forwardInvocation = extract("v@:@")
        //static let methodSignatureForSelector = extract("v@::")

        private static func extract(_ string: StaticString) -> UnsafePointer<CChar> {
            return UnsafeRawPointer(string.utf8Start).assumingMemoryBound(to: CChar.self)
        }
    }

    /// The object that is being hooked.
    let object: AnyObject

    /// Subclass that we create on the fly
    private(set) var `class`: AnyClass

    /// Hooks that have to be called dynamically.
    var hookContainer: Interpose.DynamicHookContainer? {
        get { objc_getAssociatedObject(object, &Interpose.AssociatedKeys.hookContainer)
            as? Interpose.DynamicHookContainer }
        set {
            objc_setAssociatedObject(object, &Interpose.AssociatedKeys.hookContainer,
                                     newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// If the class has been altered (e.g. via NSKVONotifying_ KVO logic)
    /// then perceived and actual class don't match.
    ///
    /// Making KVO and Object-based hooking work at the same time is difficult.
    /// If we make a dynamic subclass over KVO, invalidating the token crashes in cache_getImp.
    init(object: AnyObject) throws {
        self.object = object
        `class` = type(of: object) // satisfy set to something
        `class` = try getExistingSubclass() ?? createSubclass()
    }

    private func createSubclass() throws -> AnyClass {
        let perceivedClass: AnyClass = type(of: object)
        let actualClass: AnyClass = object_getClass(object)!

        let className = NSStringFromClass(perceivedClass)
        // Right now we are wasteful. Might be able to optimize for shared IMP?
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let subclassName = Constants.subclassSuffix + className + uuid

        let subclass: AnyClass? = subclassName.withCString { cString in
            // swiftlint:disable:next force_cast
            if let existingClass = objc_getClass(cString) as! AnyClass? {
                return existingClass
            } else {
                guard let subclass: AnyClass = objc_allocateClassPair(actualClass, cString, 0) else { return nil }
                replaceGetClass(in: subclass, decoy: perceivedClass)
                objc_registerClassPair(subclass)
                return subclass
            }
        }

        guard let nnSubclass = subclass else {
            throw InterposeError.failedToAllocateClassPair(class: perceivedClass, subclassName: subclassName)
        }

        object_setClass(object, nnSubclass)
        let oldName = NSStringFromClass(class_getSuperclass(object_getClass(object)!)!)
        Interpose.log("Generated \(NSStringFromClass(nnSubclass)) for object (was: \(oldName))")
        return nnSubclass
    }

    /// We need to reuse a dynamic subclass if the object already has one.
    private func getExistingSubclass() -> AnyClass? {
        let actualClass: AnyClass = object_getClass(object)!
        if NSStringFromClass(actualClass).hasPrefix(Constants.subclassSuffix) {
            return actualClass
        }
        return nil
    }

    /// Overrides the invocation forwarding machinery to support dynamic invocation.
    func prepareDynamicInvocation() throws {
        guard InterposeSubclass.supportsSuperTrampolines else { throw InterposeError.unknownError("SuperBuilder is required for dynamic invocation")}

        try replaceForwardInvocation()
    }

    #if !os(Linux)

    class func aspectPrefixed(_ selector: Selector) -> Selector {
        Selector("interpose_" + selector.description)
    }

    /// Test if the class requires adding dynamic implementation preparation hooks.
    private func requiresPrepareDynamicInvocation() -> Bool {
        implementsExact(selector: ObjCSelector.forwardInvocation) == false
    }

    private func replaceForwardInvocation() throws {
        guard requiresPrepareDynamicInvocation() else { return }

        // Add super trampoline
        addSuperTrampoline(selector: ObjCSelector.forwardInvocation)

        // Replace with custom handler that calls our hooks
        var origImp: IMP?
        let forwardInvocation: @convention(block) (AnyObject, ObjCInvocation) -> Void = { bSelf, invocation in

            if let hookContainer = self.hookContainer {
                hookContainer.before.executeAll(bSelf)

                // Call instead hooks or original
                let instead = hookContainer.instead
                if instead.isEmpty {
                    let selector = invocation.selector()
                    let prefixedSelector = InterposeSubclass.aspectPrefixed(selector)
                    invocation.setSelector(prefixedSelector)
                    invocation.invoke()
                } else {
                    instead.executeAll(bSelf)
                }

                hookContainer.after.executeAll(bSelf)

            } else {
                // Call original forward
                // - (void)forwardInvocation:(NSInvocation *)anInvocation
                let originalInvocation = unsafeBitCast(origImp!, to: (@convention(c) (AnyObject, Selector, AnyObject) -> Void).self)
                originalInvocation(bSelf, ObjCSelector.forwardInvocation, invocation)

            }
        }

        let impl = imp_implementationWithBlock(forwardInvocation as Any)
        origImp = try replace(selector: ObjCSelector.forwardInvocation, imp: impl, encoding: ObjCMethodEncoding.getClass)
    }

    private func replaceGetClass(in class: AnyClass, decoy perceivedClass: AnyClass) {
        // crashes on linux
        let getClass: @convention(block) (AnyObject) -> AnyClass = { _ in
            perceivedClass
        }
        let impl = imp_implementationWithBlock(getClass as Any)
        _ = class_replaceMethod(`class`, ObjCSelector.getClass, impl, ObjCMethodEncoding.getClass)
        _ = class_replaceMethod(object_getClass(`class`), ObjCSelector.getClass, impl, ObjCMethodEncoding.getClass)
    }

    class var supportsSuperTrampolines: Bool {
        NSClassFromString("SuperBuilder")?.value(forKey: "isSupportedArchitecure") as? Bool ?? false
    }

    private lazy var addSuperImpl: @convention(c) (AnyClass, Selector, NSErrorPointer) -> Bool = {
        let imp = Interpose.resolve(symbol: "IKTAddSuperImplementationToClass")
        return unsafeBitCast(imp, to: (@convention(c) (AnyClass, Selector, NSErrorPointer) -> Bool).self)
    }()

    func addSuperTrampoline(selector: Selector) {
        var error: NSError?
        if addSuperImpl(`class`, selector, &error) == false {
            Interpose.log("Failed to add super implementation to -[\(`class`).\(selector)]: \(error!)")
        } else {
            let imp = class_getMethodImplementation(`class`, selector)!
            Interpose.log("Added super for -[\(`class`).\(selector)]: \(imp)")
        }
    }
    #else
    func addSuperTrampoline(selector: Selector) { }
    class var supportsSuperTrampolines: Bool { return false }
    private func replaceGetClass(in class: AnyClass, decoy perceivedClass: AnyClass) {}
    #endif
}
