import Foundation

extension Interpose {
    /// A hook to an instance method and stores both the original and new implementation.
    final public class ClassHook<MethodSignature, HookSignature>: TypedHook<MethodSignature, HookSignature> {

        /// Initialize a new hook to interpose an instance method.
        // TODO: report compiler crash
        public init(`class`: AnyClass, selector: Selector, implementation:(ClassHook<MethodSignature, HookSignature>) -> HookSignature?)  /* This must be optional or swift runtime will crash. Or swiftc may segfault. Compiler bug? */ throws {
            try super.init(class: `class`, selector: selector)
            replacementIMP = imp_implementationWithBlock(implementation(self) as Any)
        }

        override func replaceImplementation() throws {
            let method = try validate()
            origIMP = class_replaceMethod(`class`, selector, replacementIMP, method_getTypeEncoding(method))
            guard origIMP != nil else { throw InterposeError.nonExistingImplementation(`class`, selector) }
            Interpose.log("Swizzled -[\(`class`).\(selector)] IMP: \(origIMP!) -> \(replacementIMP!)")
        }

        override func resetImplementation() throws {
            try restorePreviousIMP(exactClass: `class`)
        }

        /// The original implementation is cached at hook time.
        public override var original: MethodSignature {
           unsafeBitCast(origIMP, to: MethodSignature.self)
        }
    }
}

#if DEBUG
extension Interpose.ClassHook: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "\(selector) -> \(String(describing: origIMP))"
    }
}
#endif
