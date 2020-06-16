import Foundation

extension Interpose {

    /// A hook to an instance method of a single object, stores both the original and new implementation.
    /// Think about: Multiple hooks for one object
    final public class ObjectHook<MethodSignature, HookSignature>: TypedHook<MethodSignature, HookSignature> {

        /// The object that is being hooked.
        public let object: AnyObject

        /// Subclass that we create on the fly
        var interposeSubclass: InterposeSubclass?

        // Logic switch to use super builder
        let generatesSuperIMP = InterposeSubclass.supportsSuperTrampolines

        /// Initialize a new hook to interpose an instance method.
        public init(object: AnyObject, selector: Selector,
                    implementation: (ObjectHook<MethodSignature, HookSignature>) -> HookSignature?) throws {
            self.object = object
            try super.init(class: type(of: object), selector: selector)
            let block = implementation(self) as AnyObject
            replacementIMP = imp_implementationWithBlock(block)
            guard replacementIMP != nil else {
                throw InterposeError.unknownError("imp_implementationWithBlock failed for \(block) - slots exceeded?")
            }

            // Weakly store reference to hook inside the block of the IMP.
            Interpose.storeHook(hook: self, to: block)
        }

        //    /// Release the hook block if possible.
        //    public override func cleanup() {
        //        // remove subclass!
        //        super.cleanup()
        //    }

        /// The original implementation of the hook. Might be looked up at runtime. Do not cache this.
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
            var methodCount: CUnsignedInt = 0
            guard let methodsInAClass = class_copyMethodList(klass, &methodCount) else { return false }
            defer { free(methodsInAClass) }
            for index in 0 ..< Int(methodCount) {
                let method = methodsInAClass[index]
                if method_getName(method) == selector {
                    return true
                }
            }
            return false
        }

        var dynamicSubclass: AnyClass {
            interposeSubclass!.dynamicClass
        }

        override func replaceImplementation() throws {
            let method = try validate()

            // Check if there's an existing subclass we can reuse.
            // Create one at runtime if there is none.
            interposeSubclass = try InterposeSubclass(object: object)

            // The implementation of the call that is hooked must exist.
            guard lookupOrigIMP != nil else {
                throw InterposeError.nonExistingImplementation(`class`, selector).log()
            }

            //  This function searches superclasses for implementations
            let hasExistingMethod = exactClassImplementsSelector(dynamicSubclass, selector)
            let encoding = method_getTypeEncoding(method)

            if self.generatesSuperIMP {
                // If the subclass is empty, we create a super trampoline first.
                // If a hook already exists, we must skip this.
                if !hasExistingMethod {
                    interposeSubclass!.addSuperTrampoline(selector: selector)
                }

                // Replace IMP (by now we guarantee that it exists)
                origIMP = class_replaceMethod(dynamicSubclass, selector, replacementIMP, encoding)
                guard origIMP != nil else {
                    throw InterposeError.nonExistingImplementation(dynamicSubclass, selector)
                }
                Interpose.log("Added -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
            } else {
                // Could potentially be unified in the code paths
                if hasExistingMethod {
                    origIMP = class_replaceMethod(dynamicSubclass, selector, replacementIMP, encoding)
                    if origIMP != nil {
                        Interpose.log("Added -[\(`class`).\(selector)] IMP: \(replacementIMP!) via replacement")
                    } else {
                        Interpose.log("Unable to replace: -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
                        throw InterposeError.unableToAddMethod(`class`, selector)
                    }
                } else {
                    let didAddMethod = class_addMethod(dynamicSubclass, selector, replacementIMP, encoding)
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
            let method = try validate(expectedState: .interposed)

            guard super.origIMP != nil else {
                // Removing methods at runtime is not supported.
                // https://stackoverflow.com/questions/1315169/
                // how-do-i-remove-instance-methods-at-runtime-in-objective-c-2-0
                //
                // This codepath will be hit if the super helper is missing.
                // We could recreate the whole class at runtime and rebuild all hooks,
                // but that seesm excessive when we have a trampoline at our disposal.
                Interpose.log("Reset of -[\(`class`).\(selector)] not supported. No IMP")
                throw InterposeError.resetUnsupported("No Original IMP found. SuperBuilder missing?")
            }

            guard let currentIMP = class_getMethodImplementation(dynamicSubclass, selector) else {
                throw InterposeError.unknownError("No Implementation found")
            }

            // We are the topmost hook, replace method.
            if currentIMP == replacementIMP {
                let previousIMP = class_replaceMethod(
                    dynamicSubclass, selector, origIMP!, method_getTypeEncoding(method))
                guard previousIMP == replacementIMP else {
                    throw InterposeError.unexpectedImplementation(dynamicSubclass, selector, previousIMP)
                }
                Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")
            } else {
                let nextHook = Interpose.findNextHook(selfHook: self, topmostIMP: currentIMP)
                // Replace next's original IMP
                nextHook?.origIMP = self.origIMP
            }

            // FUTURE: remove class pair!
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
