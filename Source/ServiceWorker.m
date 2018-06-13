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

@synthesize delegate;
@synthesize workerDescription;
@synthesize amCanceling;
@synthesize runningController;


+ (id)serviceWorkerWithTarget:(id)target andAction:(SEL)action
{
    return [[self alloc] initWithTarget:target andAction:action];
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
	if (_queue) {
        return;
	}

    _queue = [[NSOperationQueue alloc] init];
    // built an invocation operation for the user-specified target/action
    ServiceWrappedArgs *wrappedArgs = [ServiceWrappedArgs wrappedArgsForWorker:self arg1:args];
    NSInvocationOperation *op = [[NSInvocationOperation alloc] 
                                  initWithTarget:_target selector:_action object:wrappedArgs];
    // wrap it in our operation so we can get a callback
    ServiceWrappedOperation *wrapped = [ServiceWrappedOperation wrappedOperation:op 
                                                          callbackTarget:self action:@selector(finishWork:)];
    [_queue addOperation:wrapped];
}

- (void)cancel
{
	if (!_queue) {
        return;
	}

    amCanceling = YES;

    @try {
		[runningController cancel];
    }
    @catch (NSException *exception) {
        // swallow anything during a cancelation
    }

    [_queue cancelAllOperations];

	[delegate workerWasCanceled:self];
}

- (void)finishWork:(id)sender
{
	if (amCanceling) {
        return;
	}

	[delegate workerDidFinish:self];
}

@end
