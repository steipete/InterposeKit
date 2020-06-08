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
*/
BOOL IKTAddSuperImplementationToClass(Class klass, SEL selector);

NS_ASSUME_NONNULL_END
