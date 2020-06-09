//
//  ITKAddSuperMethod.h
//  InterposeKit
//
//  Created by Peter Steinberger on 08.06.20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Adds an empty super implementation instance method to klass.
 If a method already exists, this will return NO.

 @note This uses inline assembly to forward the parameters to objc_msgSendSuper.
 Currently implemented architectures are x86_64 and arm64.
 (arm7 was dropped in OS 11 and i386 with macOS Catalina.)
 */
BOOL IKTAddSuperImplementationToClass(id self, Class klass, SEL selector);

NS_ASSUME_NONNULL_END
