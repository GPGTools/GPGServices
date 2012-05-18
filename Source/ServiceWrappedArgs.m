//
//  ServiceWorkerArgs.m
//  GPGServices
//
//  Created by Chris Fraire on 5/18/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "ServiceWrappedArgs.h"

@implementation ServiceWrappedArgs 

@synthesize worker = _worker;
@synthesize arg1 = _arg1;

- (void)dealloc 
{
    [_worker release];
    [_arg1 release];
    [super dealloc];
}

+ (id)wrappedArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1
{
    return [[[self alloc] initArgsForWorker:worker arg1:arg1] autorelease];
}

- (id)initArgsForWorker:(ServiceWorker *)worker arg1:(id)arg1
{
    if (self = [super init]) {
        self.worker = worker;
        self.arg1 = arg1;
    }
    return self;
}

@end
