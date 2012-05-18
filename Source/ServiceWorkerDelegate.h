//
//  GPGWorkerDelegate.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol ServiceWorkerDelegate <NSObject>

- (void)workerWasCanceled:(id)worker;
- (void)workerDidFinish:(id)worker;

@end
