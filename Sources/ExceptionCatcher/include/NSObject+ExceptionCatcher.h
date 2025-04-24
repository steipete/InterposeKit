//
//  NSObject+ExceptionCatcher.h
//  FZSwiftUtils
//
//  Created by Florian Zand on 05.04.25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (ExceptionCatcher)

+ (BOOL)catchException:(__attribute__((noescape)) void(^)(void))tryBlock
                 error:(NSError * __autoreleasing _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
