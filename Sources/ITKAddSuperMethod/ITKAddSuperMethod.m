//
//  ITKAddSuperMethod.m
//  InterposeKit
//
//  Created by Peter Steinberger on 08.06.20.
//  Copyright © 2020 PSPDFKit GmbH. All rights reserved.
//

#import "ITKAddSuperMethod.h"

@import ObjectiveC.message;
@import ObjectiveC.runtime;

NS_ASSUME_NONNULL_BEGIN

void msgSendSuperTrampoline(void);
void msgSendSuperStretTrampoline(void);

_Thread_local struct objc_super _threadSuperStorage;

struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj);
struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj) {
    struct objc_super *_super = &_threadSuperStorage;
    _super->receiver = obj;
    _super->super_class = [obj class];
    return _super;
}

/**
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

                  // get new return (adr of the objc_super class)
                  "mov x0, x9\n"
                  // tail call
                  "b _objc_msgSendSuper \n"
                  : : : "x0", "x1");
}

// arm64 doesn't use _stret variants.
void msgSendSuperStretTrampoline(void) {}

#elif defined(__x86_64__)

__attribute__((__naked__))
void msgSendSuperTrampoline(void) {
    asm volatile (
                  "pushq   %%rbp                 # push frame pointer \n"
                  "movq    %%rsp, %%rbp          # set stack to frame pointer \n"
                  "subq    $48, %%rsp            # reserve 48 byte on the stack (need 16 byte alignment) \n"

                  // Save call params: rdi, rsi, rdx, rcx, r8, r9
                  "movq    %%rdi, -8(%%rbp)      # copy self to stack[1] \n" // po *(id *)
                  "movq    %%rsi, -16(%%rbp)     # copy _cmd to stack[2] \n" // p (SEL)$rsi
                  "movq    %%rdx, -24(%%rbp) \n"
                  "movq    %%rcx, -32(%%rbp) \n"
                  "movq    %%r8,  -40(%%rbp) \n"
                  "movq    %%r9,  -48(%%rbp) \n"

                  // fetch filled struct objc_super, call with self + _cmd
                  "callq    _ITKReturnThreadSuper \n"
                  // first param is now struct objc_super
                  "movq %%rax, %%rdi \n"

                  // Restore call params
                  "movq    -16(%%rbp), %%rsi \n"
                  "movq    -24(%%rbp), %%rdx \n"
                  "movq    -32(%%rbp), %%rcx \n"
                  "movq    -40(%%rbp), %%r8  \n"
                  "movq    -48(%%rbp), %%r9  \n"

                  // remove everything to prepare tail call
                  // debug stack via print  *(int *)  ($rsp+8)
                  "addq    $48, %%rsp            # remove 64 byte from stack \n"
                  "popq    %%rbp                 # pop frame pointer \n"

                  "jmp _objc_msgSendSuper        # tail call \n"
                  : : : "rsi", "rdi");
}


__attribute__((__naked__))
void msgSendSuperStretTrampoline(void) {
    asm volatile (
                  "pushq   %%rbp                 # push frame pointer \n"
                  "movq    %%rsp, %%rbp          # set stack to frame pointer \n"
                  "subq    $48, %%rsp            # reserve 48 byte on the stack (need 16 byte alignment) \n"

                  // Save call params: rax(for va_arg) rdi, rsi, rdx, rcx, r8, r9
                  "movq    %%rdi, -8(%%rbp) \n"  // struct return
                  "movq    %%rsi, -16(%%rbp) \n" // self
                  "movq    %%rdx, -24(%%rbp) \n" // _cmd
                  "movq    %%rcx, -32(%%rbp) \n" // param 1
                  "movq    %%r8,  -40(%%rbp) \n" // param 2
                  "movq    %%r9,  -48(%%rbp) \n" // param 3

                  // fetch filled struct objc_super, call with self + _cmd
                  // Since stret offsets, we move back by one
                  "movq     -16(%%rbp), %%rdi \n"
                  "movq     -24(%%rbp), %%rdx \n"
                  "callq    _ITKReturnThreadSuper \n"
                  // second param is now struct objc_super
                  "movq %%rax, %%rsi \n"
                  // First is our struct return

                  // Restore call params
                  "movq     -8(%%rbp), %%rdi \n"
                  //"movq    -16(%%rbp), %%rsi \n"
                  "movq    -24(%%rbp), %%rdx \n"
                  "movq    -32(%%rbp), %%rcx \n"
                  "movq    -40(%%rbp), %%r8  \n"
                  "movq    -48(%%rbp), %%r9  \n"

                  // remove everything to prepare tail call
                  // debug stack via print  *(int *)  ($rsp+8)
                  "addq    $48, %%rsp            # remove 64 byte from stack \n"
                  "popq    %%rbp                 # pop frame pointer \n"

                  "jmp _objc_msgSendSuper_stret   # tail call \n"
                  : : : "rsi", "rdi");
}

#endif

typedef NS_ENUM(NSInteger, DispatchMode) {
    DispatchModeNormal,
    DispatchModeStret,
};

static DispatchMode IKTGetDispatchMode(const char *typeEncoding) {
    DispatchMode dispatchMode = DispatchModeNormal;
#if defined (__arm64__)
    // ARM64 doesn't use stret dispatch. Yay!
#elif defined (__x86_64__)
    // On x86-64, stret dispatch is ~used whenever return type doesn't fit into two registers
    //
    // http://www.sealiesoftware.com/blog/archive/2008/10/30/objc_explain_objc_msgSend_stret.html
    // x86_64 is more complicated, including rules for returning floating-point struct fields in FPU registers, and ppc64's rules and exceptions will make your head spin. The gory details are documented in the Mac OS X ABI Guide, though as usual if the documentation and the compiler disagree then the documentation is wrong.
    NSUInteger returnTypeActualSize = 0;
    NSGetSizeAndAlignment(typeEncoding, &returnTypeActualSize, NULL);
    dispatchMode = returnTypeActualSize > (sizeof(void *) * 2) ? DispatchModeStret : DispatchModeNormal;
#else
#error - Unknown architecture
#endif
    return dispatchMode;
}

BOOL IKTAddSuperImplementationToClass(id self, Class klass, SEL selector) {
    Class originalClass = klass;

    Class superClass = class_getSuperclass(originalClass);
    if (superClass == nil) {
        return NO;
    }
    Method method = class_getInstanceMethod(superClass, selector);
    if (method == NULL) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"No dynamically dispatched method with selector %@ is available on any of the superclasses of %@",
         NSStringFromSelector(selector), NSStringFromClass(originalClass)];
        return NO;
    }
    const char *typeEncoding = method_getTypeEncoding(method);
    const BOOL isNormalDispatch = IKTGetDispatchMode(typeEncoding) == DispatchModeNormal;
    IMP trampoline = isNormalDispatch ? msgSendSuperTrampoline : msgSendSuperStretTrampoline;
    BOOL methodAdded = class_addMethod(klass, selector, trampoline, typeEncoding);
    if (!methodAdded) {
        NSLog(@"Failed to add method for selector %@ to class %@",
              NSStringFromSelector(selector),
              NSStringFromClass(klass));
    }

    return methodAdded;
}

NS_ASSUME_NONNULL_END
