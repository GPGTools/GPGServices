//
//  ServiceWorker.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GPGController;
@protocol ServiceWorkerDelegate;

@interface ServiceWorker : NSObject {
//    NSString *_workerDescription;
    id _target;
    SEL _action;
    NSOperationQueue *_queue;
//    BOOL _amCanceling;
//    GPGController *_runningController;
}

@property (unsafe_unretained) id <ServiceWorkerDelegate> delegate;
@property (strong) NSString *workerDescription;
@property (readonly) BOOL amCanceling;

// ServiceWorker does not own;
// underlying operations might use to store the currently running controller 
// to allow this class's cancel to possibly interrupt a gpg2 operation
@property (strong) GPGController *runningController;

+ (id)serviceWorkerWithTarget:(id)target andAction:(SEL)action;
- (id)initWithTarget:(id)target andAction:(SEL)action;

- (void)setTarget:(id)target andAction:(SEL)action;

// start an async invoke operation for target/action;
// target/action will be passed a ServiceWrappedArgs instance
- (void)start:(id)args;
- (void)cancel;

@end
