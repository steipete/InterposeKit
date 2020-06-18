import Foundation

class InterposeSubclass {

    private enum Constants {
        static let subclassSuffix = "InterposeKit_"
    }

    enum ObjCSelector {
        static let getClass = Selector((("class")))
    }

    enum ObjCMethodEncoding {
        static let getClass = extract("#@:")

        private static func extract(_ string: StaticString) -> UnsafePointer<CChar> {
            return UnsafeRawPointer(string.utf8Start).assumingMemoryBound(to: CChar.self)
        }
    }

    /// The object that is being hooked.
    let object: AnyObject

    /// Subclass that we create on the fly
    private(set) var dynamicClass: AnyClass

    /// If the class has been altered (e.g. via NSKVONotifying_ KVO logic)
    /// then perceived and actual class don't match.
    ///
    /// Making KVO and Object-based hooking work at the same time is difficult.
    /// If we make a dynamic subclass over KVO, invalidating the token crashes in cache_getImp.
    init(object: AnyObject) throws {
        self.object = object
        dynamicClass = type(of: object) // satisfy set to something
        dynamicClass = try getExistingSubclass() ?? createSubclass()
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

    #if !os(Linux)
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
        let handle = dlopen(nil, RTLD_LAZY)
        let imp = dlsym(handle, "IKTAddSuperImplementationToClass")
        return unsafeBitCast(imp, to: (@convention(c) (AnyClass, Selector, NSErrorPointer) -> Bool).self)
    }()

    func addSuperTrampoline(selector: Selector) {
        var error: NSError?
        if addSuperImpl(dynamicClass, selector, &error) == false {
            Interpose.log("Failed to add super implementation to -[\(dynamicClass).\(selector)]: \(error!)")
        } else {
            let imp = class_getMethodImplementation(dynamicClass, selector)!
            Interpose.log("Added super for -[\(dynamicClass).\(selector)]: \(imp)")
        }
    }
    #else
    func addSuperTrampoline(selector: Selector) { }
    class var supportsSuperTrampolines: Bool { return false }
    private func replaceGetClass(in class: AnyClass, decoy perceivedClass: AnyClass) {}
    #endif
}
