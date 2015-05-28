//
//  WorkerProgressViewItem.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "WorkerProgressViewItem.h"
#import "ServiceWorker.h"

@implementation WorkerProgressViewItem
@synthesize progressIndicator=_progressIndicator;

- (BOOL)shouldAnimate {
    return YES;
}

- (IBAction)cancelTouched:(id)sender {
    ServiceWorker *worker = [self representedObject];
    [worker cancel];
}

@end
