//
//  ServiceWrappedArgs.h
//  GPGServices
//
//  Created by Chris Fraire on 5/18/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ServiceWorker;

@interface ServiceWrappedArgs : NSObject {
    ServiceWorker *_worker;
    id _arg1;
}

@property (strong) ServiceWorker *worker;
// access as id, but enforce to be NSObject
@property (strong) id arg1;

// worker and arg1 will be retained
+ (id)wrappedArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1;
- (id)initArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1;

@end
