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

struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj, SEL cmd);
struct objc_super *ITKReturnThreadSuper(__unsafe_unretained id obj, SEL cmd) {
    struct objc_super *_super = malloc(sizeof(_super));
    _super->receiver = obj;
    _super->super_class = [obj class];

    // TODO: Inefficient
    dispatch_async(dispatch_get_main_queue(), ^{
        free(_super);
    });

    return _super;
}

#if defined(__arm64__)

__attribute__((__naked__))
void msgSendSuperTrampoline(void) {
    asm volatile (
                  " sub    sp, sp, #48             ; =48  \n\t"
                  " stp    x29, x30, [sp, #32]     ; 16-byte Folded Spill  \n\t"
                  " add    x29, sp, #32            ; =32  \n\t"
                  " stur    x0, [x29, #-8]  \n\t"
                  " str    x1, [sp, #16]  \n\t"
                  " ldur    x8, [x29, #-8]  \n\t"
                  " str    x8, [sp]  \n\t"
                  " ldur    x0, [x29, #-8] \n\t"
                  " bl    _objc_opt_class \n\t"
                  " str    x0, [sp, #8] \n\t"
                  " ldr    x1, [sp, #16] \n\t"
                  " mov    x0, sp \n\t"
                  " bl    _objc_msgSendSuper  \n\t"
                  " mov    x29, x29    ; marker for objc_retainAutoreleaseReturnValue \n\t"
                  " ldp    x29, x30, [sp, #32]     ; 16-byte Folded Reload \n\t"
                  " add    sp, sp, #48             ; =48 \n\t"
                  " ret \n\t"
                  : : : "x0", "x1");
}

#elif defined(__x86_64__)

// Arguments passed: rdi, rsi, rdx, rcx, r8, r9
__attribute__((__naked__))
void msgSendSuperTrampoline(void) {
    asm volatile (
                  "pushq   %%rbp                 # push frame pointer \n\t"
                  "movq    %%rsp, %%rbp          # set stack to frame pointer \n\t"
                  "subq    $48, %%rsp            # reserve 48 byte on the stack (need 16 byte alignment) \n\t"

                  // Save call params
                  "movq    %%rdi, -8(%%rbp)      # copy self to stack[1] \n\t"
                  "movq    %%rsi, -16(%%rbp)     # copy _cmd to stack[2] \n\t"
                  "movq    %%rdx, -24(%%rbp) \n\t"
                  "movq    %%rcx, -32(%%rbp) \n\t"
                  "movq    %%r8,  -40(%%rbp) \n\t"
                  "movq    %%r9,  -48(%%rbp) \n\t"

                  // fetch filled struct objc_super, call with self + _cmd
                  "callq    _ITKReturnThreadSuper \n\t"
                  // first param is now struct objc_super
                  "movq %%rax, %%rdi \n\t"

                  // Restore call params
                  "movq    -16(%%rbp), %%rsi \n\t"
                  "movq    -24(%%rbp), %%rdx \n\t"
                  "movq    -32(%%rbp), %%rcx \n\t"
                  "movq    -40(%%rbp), %%r8  \n\t"
                  "movq    -48(%%rbp), %%r9  \n\t"

                  // remove everything to prepare tail call
                  "addq    $48, %%rsp            # remove 64 byte from stack \n\t"
                  "popq    %%rbp                 # pop frame pointer \n\t"

                  "jmp _objc_msgSendSuper        # tail call \n\t"
                  : : : "rsi", "rdi");
}

#endif

typedef NS_ENUM(NSInteger, DispatchMode) {
    DispatchMode_Normal,
    DispatchMode_Stret,
};

static DispatchMode IKTGetDispatchMode(const char * typeEncoding) {
    DispatchMode dispatchMode = DispatchMode_Normal;
#if defined (__arm64__)
    // ARM64 doesn't use stret dispatch
#elif defined (__x86_64__)
    // On x86-64, stret dispatch is used whenever return type doesn't fit into two registers
    NSUInteger returnTypeActualSize = 0;
    NSGetSizeAndAlignment(typeEncoding, &returnTypeActualSize, NULL);
    dispatchMode = returnTypeActualSize > (sizeof(void *) * 2) ? DispatchMode_Stret : DispatchMode_Normal;
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
    // Need to write asm for x64
    __unused DispatchMode dispatchMode = IKTGetDispatchMode(typeEncoding);
    BOOL methodAdded = class_addMethod(klass,
                                       selector,
                                       msgSendSuperTrampoline,
                                       typeEncoding);
    if (!methodAdded) {
        NSLog(@"Failed to add method for selector %@ to class %@",
              NSStringFromSelector(selector),
              NSStringFromClass(klass));
    }

    return methodAdded;
}

NS_ASSUME_NONNULL_END
