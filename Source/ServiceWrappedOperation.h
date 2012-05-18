//
//  ServiceWrappedOperation.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

// Wraps an NSOperation with a callback
@interface ServiceWrappedOperation : NSOperation {
    NSOperation *_operation;
    NSObject *_callbackTarget;
    SEL _callbackAction;
}

+ wrappedOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action;
- initWithOperation:(NSOperation *)operation callbackTarget:(id)target action:(SEL)action;

@end
