//
//  ServiceWrappedOperation.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "ServiceWrappedOperation.h"

@implementation ServiceWrappedOperation


+ (id)wrappedOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action
{
    return [[self alloc] initWithOperation:operation callbackTarget:target action:action];
}

- (id)initWithOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action
{
    if (self = [super init]) {
        _operation = operation;
        _callbackTarget = target;
        _callbackAction = action;
    }
    
    return self;
}

- (void)main
{
    // do the user-specified operation
    [_operation start];
    [_operation waitUntilFinished];
    if (![_operation isCancelled])
        // then do a callback operation
        [_callbackTarget performSelector:_callbackAction withObject:self];
}

- (void)cancel
{
    [_operation cancel];
}

@end
