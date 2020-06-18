import Foundation

extension Interpose {

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

        public init(object: AnyObject, selector: Selector,
                    strategy: AspectStrategy = .before,
                    implementation: @escaping (AnyObject) -> Void) throws {
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

            let hasExistingMethod = subclass.exactClassImplementsSelector(selector)
            if !hasExistingMethod {
                // Add super trampoline, then swizzle
                subclass.addSuperTrampoline(selector: selector)
                let superCallingMethod = class_getInstanceMethod(subclass.dynamicClass, selector)!

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
            //let method = try validate(expectedState: .interposed)

            // TODO
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
