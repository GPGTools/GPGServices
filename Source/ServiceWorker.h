//
//  ServiceWorker.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol ServiceWorkerDelegate;

@interface ServiceWorker : NSObject {
    NSString *_workerDescription;
    id _target;
    SEL _action;
    NSOperationQueue *_queue;
    id <ServiceWorkerDelegate> _delegate;
    BOOL _amCanceling;
}

@property (assign) id <ServiceWorkerDelegate> delegate;
@property (retain) NSString *workerDescription;
@property (readonly) BOOL amCanceling;

+ (id)serviceWorkerWithTarget:(id)target andAction:(SEL)action;
- (id)initWithTarget:(id)target andAction:(SEL)action;

- (void)setTarget:(id)target andAction:(SEL)action;

// start an async invoke operation for target/action;
// target/action will be passed a ServiceWrappedArgs instance
- (void)start:(id)args;
- (void)cancel;

@end
