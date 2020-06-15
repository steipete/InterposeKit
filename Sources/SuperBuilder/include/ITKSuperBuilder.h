#if __APPLE__
#import <Foundation/Foundation.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/**
Adds an empty super implementation instance method to originalClass.
If a method already exists, this will return NO and a descriptive error message.

Example: You have an empty UIViewController subclass and call this with viewDidLoad as selector.
The result will be code that looks similar to this:

override func viewDidLoad() {
    super.viewDidLoad()
}

What the compiler creates in following code:

- (void)viewDidLoad {
    struct objc_super _super = {
        .receiver = self,
        .super_class = object_getClass(obj);
    };
    objc_msgSendSuper2(&_super, _cmd);
}

There are a few important details:

1) We use objc_msgSendSuper2, not objc_msgSendSuper.
  The difference is minor, but important.
  objc_msgSendSuper starts looking at the current class, which would cause an endless loop
  objc_msgSendSuper2 looks for the superclass.

2) This uses a completely dynamic lookup.
  While slightly slower, this is resilient even if you change superclasses later on.

3) The resolution method calls out to C, so it could be customized to jump over specific implementations.
  (Such API is not currently exposed)

4) This uses inline assembly to forward the parameters to objc_msgSendSuper2 and objc_msgSendSuper2_stret.
  This is currently implemented architectures are x86_64 and arm64.
  armv7 was dropped in OS 11 and i386 with macOS Catalina.

@see https://steipete.com/posts/calling-super-at-runtime/
*/
@interface SuperBuilder : NSObject

/// Adds an empty super implementation instance method to originalClass.
/// If a method already exists, this will return NO and a descriptive error message.
+ (BOOL)addSuperInstanceMethodToClass:(Class)originalClass selector:(SEL)selector error:(NSError **)error;

/// Check if the instance method in `originalClass` is a super trampoline.
+ (BOOL)isSuperTrampolineForClass:(Class)originalClass selector:(SEL)selector;

/// x86-64 and ARM64 are currently supported.
@property(class, readonly) BOOL isSupportedArchitecure;

#if (defined (__arm64__) || defined (__x86_64__)) && __APPLE__
/// Helper that does not exist if architecture is not supported.
+ (BOOL)isCompileTimeSupportedArchitecure;
#endif

@end

NSString *const SuperBuilderErrorDomain;

typedef NS_ERROR_ENUM(SuperBuilderErrorDomain, SuperBuilderErrorCode) {
    SuperBuilderErrorCodeArchitectureNotSupported,
    SuperBuilderErrorCodeNoSuperClass,
    SuperBuilderErrorCodeNoDynamicallyDispatchedMethodAvailable,
    SuperBuilderErrorCodeFailedToAddMethod
};

NS_ASSUME_NONNULL_END
