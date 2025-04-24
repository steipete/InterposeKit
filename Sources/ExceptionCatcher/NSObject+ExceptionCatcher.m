//
//  NSObject+ExceptionCatcher.m
//  FZSwiftUtils
//
//  Created by Florian Zand on 05.04.25.
//

#import "include/NSObject+ExceptionCatcher.h"

@implementation NSObject (ExceptionCatcher)

+ (BOOL)catchException:(__attribute__((noescape)) void(^)(void))tryBlock
                 error:(NSError * __autoreleasing *)error
{
    @try {
        tryBlock();
        return YES;
    }
    @catch (NSException *exception) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:exception.name
                                                code:0
                                            userInfo:exception.userInfo];
        }
        return NO;
    }
}

@end
