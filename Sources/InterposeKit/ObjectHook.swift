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
                throw InterposeError.failedToAllocateClassPair(class: perceivedClass, subclassName: subclassName)
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
        public struct ObjcSuperFake {
            public var receiver: Unmanaged<AnyObject>
            public var superClass: AnyClass
        }

        private lazy var addSuperImpl: @convention(c) (AnyClass, Selector) -> Bool = {
            let handle = dlopen(nil, RTLD_LAZY)
            let imp = dlsym(handle, "IKTAddSuperImplementationToClass")
            return unsafeBitCast(imp, to: (@convention(c) (AnyClass, Selector) -> Bool).self)
        }()

        private func addSuperTrampolineMethod(subclass: AnyClass) {
            if addSuperImpl(subclass, self.selector) == false {
                Interpose.log("Failed to add super implementation to -[\(`class`).\(selector)]")
            }
        }

        /// The original implementation is looked up at runtime .
        public override var original: MethodSignature {
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

        override func replaceImplementation() throws {
            let method = try validate()

            // Register a KVO to work around any KVO issues with opposite order
            registerKVO()

            // Register subclass at runtime if we haven't already
            if dynamicSubclass == nil {
                dynamicSubclass = try createDynamicSubclass()
            }

            /*
             // Add empty trampoline that we then replace the IMP!
             addSuperTrampolineMethod(subclass: dynamicSubclass!)
             origIMP = class_replaceMethod(dynamicSubclass!, selector, replacementIMP, method_getTypeEncoding(method))
             guard origIMP != nil else { throw InterposeError.nonExistingImplementation }
             */

            guard lookupOrigIMP != nil else {
                throw InterposeError.nonExistingImplementation(`class`, selector).log()
            }

            // Since we are creating a dynamic subclass, there cannot be an existing method
            let encoding = method_getTypeEncoding(method)
            let didAddMethod = class_addMethod(dynamicSubclass!, selector, replacementIMP, encoding)
            if didAddMethod {
                Interpose.log("Added -[\(`class`).\(selector)] IMP: \(replacementIMP!)")
            } else {
                Interpose.log("Unable to add: -[\(`class`).\(selector)] IMP: \(replacementIMP!) - method already set?")
                throw InterposeError.unableToAddMethod(`class`, selector)
            }
        }

        override func resetImplementation() throws {
            _ = try validate(expectedState: .interposed)

            guard let dynamicSubclass = self.dynamicSubclass else { preconditionFailure("No dynamic subclass set") }

            // Removing methods at runtime is not supported.
            // https://stackoverflow.com/questions/1315169/how-do-i-remove-instance-methods-at-runtime-in-objective-c-2-0

            // Instead, we have to recreate the whole subclass
            // Temporary, to remove objc override
            _ = try createDynamicSubclass()

            // Dispose of the custom dynamic subclass
            objc_disposeClassPair(dynamicSubclass)
            self.dynamicSubclass = nil



            // TODO: recreate subclass completely
            /*
            let previousIMP = class_replaceMethod(dynamicSubclass, selector, _objc_msgForward, method_getTypeEncoding(method))
            guard previousIMP == replacementIMP else { throw InterposeError.unexpectedImplementation(`class`, selector, previousIMP) }
            Interpose.log("Restored -[\(`class`).\(selector)] IMP: \(origIMP!)")

            // Restore the original class of the object
            // Does this include the KVO'ed subclass?
            object_setClass(object, `class`)
            */

//
//            // Remove KVO after restoring class as last step.
//            deregisterKVO()
        }


        // MARK: KVO Helper

        var kvoObserver: KVOObserver?

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
        private func registerKVO() {
            kvoObserver = KVOObserver(object: object)
        }

        private func deregisterKVO() {
            kvoObserver = nil
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
