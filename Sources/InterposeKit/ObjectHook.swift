import Foundation

extension Interpose {

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

    /// A hook to an instance method of a single object, stores both the original and new implementation.
    /// Think about: Multiple hooks for one object
    final public class ObjectHook<MethodSignature, HookSignature>: TypedHook<MethodSignature, HookSignature> {
        public let object: AnyObject
        /// Subclass that we create on the fly
        var dynamicSubclass: AnyClass?

        // Logic switch to use super builder
        let generatesSuperIMP = true

        /// Initialize a new hook to interpose an instance method.
        public init(object: AnyObject, selector: Selector, implementation:(ObjectHook<MethodSignature, HookSignature>) -> HookSignature?) throws {
            self.object = object
            try super.init(class: type(of: object), selector: selector)
            replacementIMP = imp_implementationWithBlock(implementation(self) as Any)
        }

        //    /// Release the hook block if possible.
        //    public override func cleanup() {
        //        // remove subclass!
        //        super.cleanup()
        //    }

        /// Creates a unique dynamic subclass of the current object
        private func createDynamicSubclass() throws -> AnyClass {

            // If the class has been altered (e.g. via NSKVONotifying_ KVO logic)
            // then perceived and actual class don't match.
            //
            // Making KVO and Object-based hooking work at the same time is difficult.
            // If we make a dynamic subclass over KVO, invalidating the token crashes in cache_getImp.

            let perceivedClass: AnyClass = `class`
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
                    if let subclass: AnyClass = objc_allocateClassPair(actualClass, cString, 0) {
                        replaceGetClass(in: subclass, decoy: perceivedClass)
                        objc_registerClassPair(subclass)
                        return subclass
                    } else {
                        return nil
                    }
                }
            }

            guard let nonnullSubclass = subclass else {
                throw InterposeError.failedToAllocateClassPair(class: perceivedClass, subclassName: subclassName)
            }

            object_setClass(object, nonnullSubclass)
            Interpose.log("Generated \(NSStringFromClass(nonnullSubclass)) for object (was: \(NSStringFromClass(class_getSuperclass(object_getClass(object)!)!)))")
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

        private lazy var addSuperImpl: @convention(c) (AnyClass, Selector) -> Bool = {
            let handle = dlopen(nil, RTLD_LAZY)
            let imp = dlsym(handle, "IKTAddSuperImplementationToClass")
            return unsafeBitCast(imp, to: (@convention(c) (AnyClass, Selector) -> Bool).self)
        }()

        private func addSuperTrampolineMethod(subclass: AnyClass) {
            if addSuperImpl(subclass, self.selector) == false {
                // TODO: use error log!
                Interpose.log("Failed to add super implementation to -[\(`class`).\(selector)]")
            } else {
                let imp = class_getMethodImplementation(subclass, self.selector)!
                Interpose.log("Added super for -[\(`class`).\(selector)]: \(imp)")
            }
        }

        /// The original implementation is looked up at runtime .
        public override var original: MethodSignature {
            // If we switched implementations, return stored.
            if let savedOrigIMP = origIMP {
                return unsafeBitCast(savedOrigIMP, to: MethodSignature.self)
            }
            // Else, perform a dynamic lookup
            guard let origIMP = lookupOrigIMP else { InterposeError.nonExistingImplementation(`class`, selector).log()
                preconditionFailure("IMP must be found for call")
            }
            return origIMP
        }

        /// We look for the parent IMP dynamically, so later modifications to the class are no problem.
        private var lookupOrigIMP: MethodSignature? {
            var currentClass: AnyClass? = self.class
            repeat {
                if let currentClass = currentClass,
                    let method = class_getInstanceMethod(currentClass, self.selector) {
                    let origIMP = method_getImplementation(method)
                    return unsafeBitCast(origIMP, to: MethodSignature.self)
                }
                currentClass = class_getSuperclass(currentClass)
            } while currentClass != nil
            return nil
        }

        /// Looks for an instance method in the exact class, without looking up the hierarchy.
        func exactClassImplementsSelector(_ klass: AnyClass, _ selector: Selector) -> Bool {
            var methodCount : CUnsignedInt = 0
            guard let methodsInAClass = class_copyMethodList(klass, &methodCount) else { return false }
            defer { free(methodsInAClass) }
            for i in 0 ..< Int(methodCount) {
                let method = methodsInAClass[i]
                if method_getName(method) == selector {
                    return true
                }
            }
            return false
        }

        override func replaceImplementation() throws {
            let method = try validate()

            // Register subclass at runtime if we haven't already
            if dynamicSubclass == nil {
                dynamicSubclass = try createDynamicSubclass()
            }

            guard lookupOrigIMP != nil else {
                throw InterposeError.nonExistingImplementation(`class`, selector).log()
            }

            let encoding = method_getTypeEncoding(method)
            //  This function searches superclasses for implementations
            let hasExistingMethod = exactClassImplementsSelector(dynamicSubclass!, selector)

            if self.generatesSuperIMP {

                // If the subclass is empty, we create a super trampoline first.
                // If a hook already exists, we must skip this.
                if !hasExistingMethod {
                    addSuperTrampolineMethod(subclass: dynamicSubclass!)
                }

                // Replace IMP (by now we guarantee that it exists)
                origIMP = class_replaceMethod(dynamicSubclass!, selector, replacementIMP, encoding)
                guard origIMP != nil else {
                    throw InterposeError.nonExistingImplementation(dynamicSubclass!, selector)
                }
                Interpose.log("Added -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
            } else {
                if hasExistingMethod {
                    origIMP = class_replaceMethod(dynamicSubclass!, selector, replacementIMP, encoding)
                    if origIMP != nil {
                        Interpose.log("Added -[\(`class`).\(selector)] IMP: \(replacementIMP!) via replacement")
                    } else {
                        Interpose.log("Unable to replace: -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
                        throw InterposeError.unableToAddMethod(`class`, selector)
                    }
                } else {
                    let didAddMethod = class_addMethod(dynamicSubclass!, selector, replacementIMP, encoding)
                    if didAddMethod {
                        Interpose.log("Added -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
                    } else {
                        Interpose.log("Unable to add: -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
                        throw InterposeError.unableToAddMethod(`class`, selector)
                    }
                }
            }
        }

        override func resetImplementation() throws {
            _ = try validate(expectedState: .interposed)

            if super.origIMP != nil {
                try restorePreviousIMP(exactClass: dynamicSubclass!)
            } else {
                // Removing methods at runtime is not supported.
                // https://stackoverflow.com/questions/1315169/how-do-i-remove-instance-methods-at-runtime-in-objective-c-2-0
                //
                // This codepath will be hit if the super helper is missing.
                // We could recreate the whole class at runtime and rebuild all hooks,
                // but that seesm excessive when we have a trampoline at our disposal.
                Interpose.log("Reset of -[\(`class`).\(selector)] not supported. No Original IMP")
            }

            // TODO: remove class pair!
            // This might fail if we get KVO observed.
            // objc_disposeClassPair does not return a bool but logs if it fails.
            //
            // objc_disposeClassPair(dynamicSubclass)
            // self.dynamicSubclass = nil
        }
    }
}

#if DEBUG
extension Interpose.ObjectHook: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) of \(object) -> \(String(describing: original))"
    }
}
#endif
