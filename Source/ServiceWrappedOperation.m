//
//  ServiceWrappedOperation.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "ServiceWrappedOperation.h"

@implementation ServiceWrappedOperation

- (void)dealloc
{
    [_operation release];
    [_callbackTarget release];
    [super dealloc];
}

+ (id)wrappedOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action
{
    return [[[self alloc] initWithOperation:operation callbackTarget:target action:action] autorelease];
}

- (id)initWithOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action
{
    if (self = [super init]) {
        _operation = [operation retain];
        _callbackTarget = [target retain];
        _callbackAction = action;
    }
    
    return self;
}

- (void)main
{
    [_operation start];
    [_operation waitUntilFinished];
    if (![_operation isCancelled])
        [_callbackTarget performSelector:_callbackAction withObject:self];
}

- (void)cancel
{
    [_operation cancel];
}

@end
