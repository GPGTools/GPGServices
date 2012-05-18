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

@property (retain) ServiceWorker *worker;
// access as id, but enforce to be NSObject
@property (retain) id arg1;

+ (id)wrappedArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1;
- (id)initArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1;

@end
