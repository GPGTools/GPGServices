//
//  ServiceWorker.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "ServiceWorker.h"
#import "ServiceWorkerDelegate.h"
#import "ServiceWrappedOperation.h"
#import "ServiceWrappedArgs.h"
#import "Libmacgpg/GPGController.h"

@interface ServiceWorker ()
- (void)finishWork:(id)sender;
@end

@implementation ServiceWorker 

@synthesize delegate = _delegate;
@synthesize workerDescription = _workerDescription;
@synthesize amCanceling = _amCanceling;
@synthesize runningController = _runningController;

- (void)dealloc 
{
    [_workerDescription release];
    [_queue release];
    [_runningController release];
    [super dealloc];
}

+ (id)serviceWorkerWithTarget:(id)target andAction:(SEL)action
{
    return [[[self alloc] initWithTarget:target andAction:action] autorelease];
}

- (id)initWithTarget:(id)target andAction:(SEL)action
{
    if (self = [super init]) {
        [self setTarget:target andAction:action];
    }
    return self;
}

- (void)setTarget:(id)target andAction:(SEL)action
{
    _target = target;
    _action = action;
}

- (void)start:(id)args 
{
    if (_queue) 
        return;

    _queue = [[NSOperationQueue alloc] init];
    // built an invocation operation for the user-specified target/action
    ServiceWrappedArgs *wrappedArgs = [ServiceWrappedArgs wrappedArgsForWorker:self arg1:args];
    NSInvocationOperation *op = [[[NSInvocationOperation alloc] 
                                  initWithTarget:_target selector:_action object:wrappedArgs] autorelease];
    // wrap it in our operation so we can get a callback
    ServiceWrappedOperation *wrapped = [ServiceWrappedOperation wrappedOperation:op 
                                                          callbackTarget:self action:@selector(finishWork:)];
    [_queue addOperation:wrapped];
}

- (void)cancel
{
    if (!_queue)
        return;

    _amCanceling = YES;

    GPGController *gpc = [[_runningController retain] autorelease];
    @try {
        if (gpc)
            [gpc cancel];
    }
    @catch (NSException *exception) {
        // swallow anything during a cancelation
    }

    [_queue cancelAllOperations];

    if (_delegate)
        [_delegate workerWasCanceled:self];
}

- (void)finishWork:(id)sender
{
    if (_amCanceling)
        return;

    if (_delegate)
        [_delegate workerDidFinish:self];
}

@end
