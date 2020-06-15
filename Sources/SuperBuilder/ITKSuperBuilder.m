#if __APPLE__
#import "ITKSuperBuilder.h"

@import ObjectiveC.message;
@import ObjectiveC.runtime;

NS_ASSUME_NONNULL_BEGIN

NSString *const SuperBuilderErrorDomain = @"com.steipete.superbuilder";

void msgSendSuperTrampoline(void);
void msgSendSuperStretTrampoline(void);

#define let const __auto_type
#define var __auto_type

static IMP ITKGetTrampolineForTypeEncoding(__unused const char *typeEncoding) {
    BOOL requiresStructDispatch = NO;
    #if defined (__arm64__)
    // ARM64 doesn't use stret dispatch. Yay!
    #elif defined (__x86_64__)
        // On x86-64, stret dispatch is ~used whenever return type doesn't fit into two registers
        //
        // http://www.sealiesoftware.com/blog/archive/2008/10/30/objc_explain_objc_msgSend_stret.html
        // x86_64 is more complicated, including rules for returning floating-point struct fields in FPU registers, and ppc64's rules and exceptions will make your head spin. The gory details are documented in the Mac OS X ABI Guide, though as usual if the documentation and the compiler disagree then the documentation is wrong.
        NSUInteger returnTypeActualSize = 0;
        NSGetSizeAndAlignment(typeEncoding, &returnTypeActualSize, NULL);
        requiresStructDispatch = returnTypeActualSize > (sizeof(void *) * 2);
    #else
    // Unknown architecture
    // https://devblogs.microsoft.com/xamarin/apple-new-processor-architecture/
    // watchOS uses arm64_32 since series 4, before armv7k. watch Simulator uses i386.
    // See ILP32: http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dai0490a/ar01s01.html
    #endif

    return requiresStructDispatch ? (IMP)msgSendSuperStretTrampoline : (IMP)msgSendSuperTrampoline;
}

// Helper for binding with Swift
BOOL IKTAddSuperImplementationToClass(Class originalClass, SEL selector, NSError **error);
BOOL IKTAddSuperImplementationToClass(Class originalClass, SEL selector, NSError **error) {
    return [SuperBuilder addSuperInstanceMethodToClass:originalClass selector:selector error:error];
}

#define ERROR_AND_RETURN(CODE, STRING)\
if (error) { *error = [NSError errorWithDomain:SuperBuilderErrorDomain code:CODE userInfo:@{NSLocalizedDescriptionKey: STRING}];} return NO;

@implementation SuperBuilder

+ (BOOL)isSupportedArchitecure {
#if defined (__arm64__) || defined (__x86_64__)
    return YES;
#else
    return NO;
#endif
}

#if defined (__arm64__) || defined (__x86_64__)
+ (BOOL)isCompileTimeSupportedArchitecure {
    return [self isSupportedArchitecure];
}
#endif

+ (BOOL)isSuperTrampolineForClass:(Class)originalClass selector:(SEL)selector {
    // No architecture check needed - will just be NO.
    let method = class_getInstanceMethod(originalClass, selector);
    return ITKMethodIsSuperTrampoline(method);
}

+ (BOOL)addSuperInstanceMethodToClass:(Class)originalClass selector:(SEL)selector error:(NSError **)error {
    if (!self.isSupportedArchitecure) {
        let msg = @"Unsupported Architecture. (Support includes ARM64 and x86-64 )";
        ERROR_AND_RETURN(SuperBuilderErrorCodeArchitectureNotSupported, msg)
    }

    // Check that class has a superclass
    let superClass = class_getSuperclass(originalClass);
    if (superClass == nil) {
        let msg = [NSString stringWithFormat:@"Unable to find superclass for %@", NSStringFromClass(originalClass)];
        ERROR_AND_RETURN(SuperBuilderErrorCodeNoSuperClass, msg)
    }

    // Fetch method called with super
    let method = class_getInstanceMethod(superClass, selector);
    if (method == NULL) {
        let msg = [NSString stringWithFormat:@"No dynamically dispatched method with selector %@ is available on any of the superclasses of %@", NSStringFromSelector(selector), NSStringFromClass(originalClass)];
        ERROR_AND_RETURN(SuperBuilderErrorCodeNoDynamicallyDispatchedMethodAvailable, msg)
    }

    // Add trampoline
    let typeEncoding = method_getTypeEncoding(method);
    let trampoline = ITKGetTrampolineForTypeEncoding(typeEncoding);
    let methodAdded = class_addMethod(originalClass, selector, trampoline, typeEncoding);
    if (!methodAdded) {
        let msg = [NSString stringWithFormat:@"Failed to add method for selector %@ to class %@", NSStringFromSelector(selector), NSStringFromClass(originalClass)];
        ERROR_AND_RETURN(SuperBuilderErrorCodeFailedToAddMethod, msg)
    }
    return methodAdded;
}

// Control if the trampoline should also push/pop the floating point registers.
// This is slightly slower and not needed for our simple implementation
// However, even if you just use memcpy, you will want to enable this.
// We keep this enabled to be doubly safe.
#define PROTECT_FLOATING_POINT_REGISTERS 1

// One thread local per thread should be enough
_Thread_local struct objc_super _threadSuperStorage;

static BOOL ITKMethodIsSuperTrampoline(Method method) {
    let methodIMP = method_getImplementation(method);
    return methodIMP == (IMP)msgSendSuperTrampoline || methodIMP == (IMP)msgSendSuperStretTrampoline;
}

struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj, SEL _cmd);
struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj, SEL _cmd) {
    /**
     Assume you have a class hierarchy made of four classes `Level1` <- `Level2` <- `Level3` <- `Level4`,
     with `Level1` implementing a method called `-sayHello`, not implemented elsewhere in descendants classes.

     If you use: `[SuperBuilder addSuperInstanceMethodToClass:Level2.class selector:@selector(sayHello) error:NULL];`
     to inject a _dummy_ implementation at `Level2`, the following will happen:

     - Calling `-[Level2 sayHello]` works. The trampoline is called, the `super_class ` is found to be `Level1`, and the `-sayHello` parent implementation is called.
     - Calling `-[LevelN sayHello]` for any N > 2 ends in an infinite recursion. Since the `obj` passed to the trampoline is a descendant of `Level2`, `objc_msgSendSuper2` will of course call the injected implementation on `Level2`, which in turn will call itself with the same arguments, again and again.

     This is fixed by walking up the hierarchy until we find the class implementing the method.

     Looking at the method implementation we can also skip subsequent super calls.
     */
    Class clazz = object_getClass(obj);
    Class superclazz = class_getSuperclass(clazz);
    do {
        let superclassMethod = class_getInstanceMethod(superclazz, _cmd);
        let sameMethods = class_getInstanceMethod(clazz, _cmd) == superclassMethod;
        if (!sameMethods && !ITKMethodIsSuperTrampoline(superclassMethod)) {
            break;
        }
        clazz = superclazz;
        superclazz = class_getSuperclass(clazz);
    }while (1);

    struct objc_super *_super = &_threadSuperStorage;
    _super->receiver = obj;
    _super->super_class = clazz;
    return _super;
}

@end

/**
 Inline assembly is used to perfectly forward all parameters to objc_msgSendSuper,
 while also looking up the target on-the-fly.

 Assembly is hard, here are some useful resources:

 https://azeria-labs.com/functions-and-the-stack-part-7/
 https://github.com/DavidGoldman/InspectiveC/blob/master/InspectiveCarm64.mm
 https://blog.nelhage.com/2010/10/amd64-and-va_arg/
 https://developer.apple.com/library/ios/documentation/Xcode/Conceptual/iPhoneOSABIReference/Articles/ARM64FunctionCallingConventions.html
 https://c9x.me/compile/bib/abi-arm64.pdf
 http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.dui0801a/BABBDBAD.html
 https://community.arm.com/developer/ip-products/processors/b/processors-ip-blog/posts/using-the-stack-in-aarch64-implementing-push-and-pop
 https://www.cs.yale.edu/flint/cs421/papers/x86-asm/asm.html
 https://eli.thegreenplace.net/2011/09/06/stack-frame-layout-on-x86-64
 https://en.wikipedia.org/wiki/Calling_convention#x86_(32-bit)
 https://bob.cs.sonoma.edu/IntroCompOrg-RPi/sec-varstack.html
 https://azeria-labs.com/functions-and-the-stack-part-7/
 */

#if defined(__arm64__)

__attribute__((__naked__))
void msgSendSuperTrampoline(void) {
    asm volatile (

#if PROTECT_FLOATING_POINT_REGISTERS
                  // push {q0-q7} floating point registers
                  "stp q6, q7, [sp, #-32]!\n"
                  "stp q4, q5, [sp, #-32]!\n"
                  "stp q2, q3, [sp, #-32]!\n"
                  "stp q0, q1, [sp, #-32]!\n"
#endif

                  // push {x0-x8, lr} (call params are: x0-x7)
                  // stp: store pair of registers: from, from, to, via indexed write
                  "stp x8, lr, [sp, #-16]!\n" // push lr (link register == x30), then x8
                  "stp x6, x7, [sp, #-16]!\n"
                  "stp x4, x5, [sp, #-16]!\n"
                  "stp x2, x3, [sp, #-16]!\n" // push x3, then x2
                  "stp x0, x1, [sp, #-16]!\n" // push x1, then x0

                  // fetch filled struct objc_super, call with self + _cmd
                  "bl _ITKReturnThreadSuper \n"

                  // first param is now struct objc_super (x0)
                  // protect returned new value when we restore the pairs
                  "mov x9, x0\n"

                  // pop {x0-x8, lr}
                  "ldp x0, x1, [sp], #16\n"
                  "ldp x2, x3, [sp], #16\n"
                  "ldp x4, x5, [sp], #16\n"
                  "ldp x6, x7, [sp], #16\n"
                  "ldp x8, lr, [sp], #16\n"

#if PROTECT_FLOATING_POINT_REGISTERS
                  // pop {q0-q7}
                  "ldp q6, q7, [sp], #32\n"
                  "ldp q4, q5, [sp], #32\n"
                  "ldp q2, q3, [sp], #32\n"
                  "ldp q0, q1, [sp], #32\n"
#endif

                  // get new return (adr of the objc_super class)
                  "mov x0, x9\n"
                  // tail call
                  "b _objc_msgSendSuper2 \n"
                  : : : "x0", "x1");
}

// arm64 doesn't use _stret variants.
void msgSendSuperStretTrampoline(void) {}

#elif defined(__x86_64__)

__attribute__((__naked__))
void msgSendSuperTrampoline(void) {
    asm volatile (
                  //  push frame pointer
                  "pushq %%rbp \n"
                  // set stack to frame pointer
                  "movq %%rsp, %%rbp \n"

#if PROTECT_FLOATING_POINT_REGISTERS
                  // reserve 48+4*16 = 112 byte on the stack (need 16 byte alignment)
                  "subq $112, %%rsp \n"

                  "movdqu %%xmm0,  -64(%%rbp) \n"
                  "movdqu %%xmm1,  -80(%%rbp) \n"
                  "movdqu %%xmm2,  -96(%%rbp) \n"
                  "movdqu %%xmm3, -112(%%rbp) \n"
#else
                  // reserve 48 byte on the stack (need 16 byte alignment)
                  "subq $48, %%rsp \n"
#endif

                  // Save call params: rdi, rsi, rdx, rcx, r8, r9
                  //
                  // First parameter can be avoided,
                  // but we need to keep the stack 16-byte algined.
                  //"movq %%rdi, -8(%%rbp)  \n" // self po *(id *)
                  "movq %%rsi, -16(%%rbp) \n" // _cmd p (SEL)$rsi
                  "movq %%rdx, -24(%%rbp) \n" // param 1
                  "movq %%rcx, -32(%%rbp) \n" // param 2
                  "movq %%r8,  -40(%%rbp) \n" // param 3
                  "movq %%r9,  -48(%%rbp) \n" // param 4 (rest goes on stack)

                  // fetch filled struct objc_super, call with self + _cmd
                  "callq _ITKReturnThreadSuper \n"
                  // first param is now struct objc_super
                  "movq %%rax, %%rdi \n"

#if PROTECT_FLOATING_POINT_REGISTERS
                  "movdqu -64(%%rbp),  %%xmm0 \n"
                  "movdqu -80(%%rbp),  %%xmm1 \n"
                  "movdqu -96(%%rbp),  %%xmm2 \n"
                  "movdqu -112(%%rbp), %%xmm3 \n"
#endif

                  // Restore call params
                  // do not restore first parameter: super class
                  "movq -16(%%rbp), %%rsi \n"
                  "movq -24(%%rbp), %%rdx \n"
                  "movq -32(%%rbp), %%rcx \n"
                  "movq -40(%%rbp), %%r8  \n"
                  "movq -48(%%rbp), %%r9  \n"

                  // debug stack via print  *(int *)  ($rsp+8)
                  // remove 112/48 byte from stack
#if PROTECT_FLOATING_POINT_REGISTERS
                  "addq $112, %%rsp \n"
#else
                  "addq $48, %%rsp \n"
#endif
                  // pop frame pointer
                  "popq  %%rbp \n"

                  // tail call time!
                  "jmp _objc_msgSendSuper2 \n"
                  : : : "rsi", "rdi");
}


__attribute__((__naked__))
void msgSendSuperStretTrampoline(void) {
    asm volatile (
                  //  push frame pointer
                  "pushq %%rbp \n"
                  // set stack to frame pointer
                  "movq %%rsp, %%rbp \n"
                  // reserve 48 byte on the stack (need 16 byte alignment)
                  "subq $48, %%rsp \n"

                  // Save call params: rdi, rsi, rdx, rcx, r8, r9
                  "movq %%rdi, -8(%%rbp) \n"  // struct return
                  "movq %%rsi, -16(%%rbp) \n" // self
                  "movq %%rdx, -24(%%rbp) \n" // _cmd
                  "movq %%rcx, -32(%%rbp) \n" // param 1
                  "movq %%r8,  -40(%%rbp) \n" // param 2
                  "movq %%r9,  -48(%%rbp) \n" // param 3 (rest goes on stack)

                  // fetch filled struct objc_super, call with self + _cmd
                  // Since stret offsets, we move back by one
                  "movq -16(%%rbp), %%rdi \n"
                  "movq -24(%%rbp), %%rsi \n"
                  "callq _ITKReturnThreadSuper \n"
                  // second param is now struct objc_super
                  "movq %%rax, %%rsi \n"
                  // First is our struct return

                  // Restore call params
                  "movq -8(%%rbp), %%rdi \n"
                  // do not restore second parameter: super class
                  "movq -24(%%rbp), %%rdx \n"
                  "movq -32(%%rbp), %%rcx \n"
                  "movq -40(%%rbp), %%r8  \n"
                  "movq -48(%%rbp), %%r9  \n"

                  // debug stack via print  *(int *)  ($rsp+8)
                  // remove 64 byte from stack
                  "addq $48, %%rsp \n"
                  // pop frame pointer
                  "popq  %%rbp \n"

                  // tail call time!
                  "jmp _objc_msgSendSuper2_stret  \n"
                  : : : "rsi", "rdi");
}

#else
// Unknown architecture - time to write some assembly :)
void msgSendSuperTrampoline(void) {}
void msgSendSuperStretTrampoline(void) {}
#endif

NS_ASSUME_NONNULL_END
#endif
