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
        var subclass: InterposeSubclass!

        // Logic switch to use super builder
        let makesSuperIMP: Bool

        public init(object: AnyObject,
                    selector: Selector,
                    strategy: AspectStrategy = .before,
                    makeSuper: Bool = true,
                    implementation: @escaping (AnyObject) -> Void) throws {
            if makeSuper && !InterposeSubclass.supportsSuperTrampolines {
                throw InterposeError.superTrampolineNotAvailable
            }

            self.object = object
            self.strategy = strategy
            self.action = implementation
            self.makesSuperIMP = makeSuper
            try super.init(class: type(of: object), selector: selector)
        }

        private lazy var forwardIMP: IMP = {
            resolve(symbol: "_objc_msgForward")
        }()

        // stret is needed for x86-64 struct returns but not for ARM64
        private lazy var forwardStretIMP: IMP = {
            resolve(symbol: "_objc_msgForward_stret")
        }()

        override func replaceImplementation() throws {
            let method = try validate()

            // Check if there's an existing subclass we can reuse.
            // Create one at runtime if there is none.
            let subclass = try InterposeSubclass(object: object)
            try subclass.prepareDynamicInvocation()
            self.subclass = subclass

            // If there is no existing implementation, add one.
            if !subclass.implementsExact(selector: selector) {
                // Add super trampoline, then swizzle
                subclass.addSuperTrampoline(selector: selector)
                let superCallingMethod = subclass.instanceMethod(selector)!

                // add a prefixed copy of the method
                let aspectSelector = InterposeSubclass.aspectPrefixed(selector)
                let origImp = superCallingMethod.implementation

                try subclass.add(selector: aspectSelector, imp: origImp, encoding: method.typeEncoding)

                Interpose.log("maked -[\(`class`).\(aspectSelector)]: \(origImp)")
            }

            // append hook as copy
            let newContainer = DynamicHookContainer()
            var hooks = subclass.hookContainer?.hooks ?? []
            hooks.append(self)
            newContainer.hooks = hooks
            subclass.hookContainer = newContainer

            try subclass.replace(method: method, imp: self.forwardIMP)
            Interpose.log("Added dynamic -[\(`class`).\(selector)]")
        }

        override func resetImplementation() throws {
            let method = try validate(expectedState: .interposed)

            // Get the super-implementation via the prefixed method...
            let aspectSelector = InterposeSubclass.aspectPrefixed(selector)

            let superIMP = try subclass.methodImplementation(aspectSelector)

            // ... and replace the original
            // The subclassed method can't be removed, but will be unused.
            let origIMP = try subclass.replace(method: method, imp: superIMP)

            // If the IMP does not match our expectations, throw!
            // TODO: guard for dynamic + static hook mix!
            guard origIMP == forwardIMP else {
                throw InterposeError.unexpectedImplementation(subclass.class, selector, origIMP)
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
