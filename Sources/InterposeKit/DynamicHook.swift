import Foundation

extension Interpose {

    public enum AspectStrategy {
        case before  /// Called before the original implementation.
        case instead /// Called insted of the original implementation.
        case after   /// Called after the original implementation.
    }

    /// Hook that uses `NSInvocation `to not require specific signatures
    /// The call is converted into an invocation via `_objc_msgForward`.
    final public class DynamicHook: AnyHook {

        /// The object that is being hooked.
        public let object: AnyObject

        /// The position of this hook.
        public let strategy: AspectStrategy

        /// The stored action to be called
        public let action: (AnyObject) -> Void

        /// Subclass that we create on the fly
        var interposeSubclass: InterposeSubclass?

        // Logic switch to use super builder
        let generatesSuperIMP: Bool

        public init(object: AnyObject,
                    selector: Selector,
                    strategy: AspectStrategy = .before,
                    generateSuper: Bool = true,
                    implementation: @escaping (AnyObject) -> Void) throws {
            if generateSuper && !InterposeSubclass.supportsSuperTrampolines {
                throw InterposeError.superTrampolineNotAvailable
            }
            self.generatesSuperIMP = generateSuper

            self.object = object
            self.strategy  = strategy
            self.action = implementation
            try super.init(class: type(of: object), selector: selector)
        }

        private lazy var forwardIMP: IMP = {
            let imp = dlsym(dlopen(nil, RTLD_LAZY), "_objc_msgForward")
            return unsafeBitCast(imp, to: IMP.self)
        }()

        override func replaceImplementation() throws {
            let method = try validate()
            let encoding = method_getTypeEncoding(method)

            // Check if there's an existing subclass we can reuse.
            // Create one at runtime if there is none.
            let subclass = try InterposeSubclass(object: object)
            try subclass.prepareDynamicInvocation()
            interposeSubclass = subclass

            // If there is no existing implementation, add one.
            if !subclass.exactClassImplements(selector: selector) {
                // Add super trampoline, then swizzle
                subclass.addSuperTrampoline(selector: selector)
                let superCallingMethod = class_getInstanceMethod(subclass.dynamicClass, selector)!

                // add a prefixed copy of the method
                let aspectSelector = InterposeSubclass.aspectPrefixed(selector)
                let origImp = method_getImplementation(superCallingMethod)
                class_addMethod(subclass.dynamicClass, aspectSelector, origImp, encoding)
                Interpose.log("Generated -[\(`class`).\(aspectSelector)]: \(origImp)")
            }

            // append hook as copy
            let newContainer = DynamicHookContainer()
            var hooks = subclass.hookContainer?.hooks ?? []
            hooks.append(self)
            newContainer.hooks = hooks
            subclass.hookContainer = newContainer

            let forwardIMP = self.forwardIMP
            guard class_replaceMethod(subclass.dynamicClass, selector, forwardIMP, encoding) != nil else {
                throw InterposeError.unableToAddMethod(subclass.dynamicClass, selector)
            }

            Interpose.log("Added dynamic -[\(`class`).\(selector)]")
        }

        override func resetImplementation() throws {
            let method = try validate(expectedState: .interposed)

            // Get the super-implementation via the prefixed method...
            let aspectSelector = InterposeSubclass.aspectPrefixed(selector)
            guard let dynamicClass = interposeSubclass?.dynamicClass,
                let superIMP = class_getMethodImplementation(dynamicClass, aspectSelector) else {
                    throw InterposeError.unknownError("Unable to get subclass or met")
            }

            // ... and replace the original
            // The subclassed method can't be removed, but will be unused.
            let encoding = method_getTypeEncoding(method)
            let origIMP = class_replaceMethod(dynamicClass, selector, superIMP, encoding)

            // If the IMP does not match our expectations, throw!
            // TODO: guard for dynamic + static hook mix!
            guard origIMP == forwardIMP else {
                throw InterposeError.unexpectedImplementation(dynamicClass, selector, origIMP)
            }

            Interpose.log("Removed dynamic -[\(`class`).\(selector)]")
        }
    }

    /// Store all hooks
    class DynamicHookContainer {
        var hooks: [DynamicHook] = []

        var before: [DynamicHook] {
            hooks.filter { $0.strategy == .before }
        }
        var instead: [DynamicHook] {
            hooks.filter { $0.strategy == .instead }
        }
        var after: [DynamicHook] {
            hooks.filter { $0.strategy == .after }
        }
    }
}

extension Collection where Iterator.Element == Interpose.DynamicHook {
    func executeAll(_ bSelf: AnyObject) {
        forEach { $0.action(bSelf) }
    }
}
