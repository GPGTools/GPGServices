//
//  InProgressController.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class ServiceWorker;

@interface InProgressWindowController : NSWindowController {
    NSTimer *_delayTimer;
}

@property (weak) IBOutlet NSCollectionView *collectionView;
@property (strong) IBOutlet NSArrayController *arrayController;
@property (strong) IBOutlet NSMutableArray<ServiceWorker *> *serviceWorkerArray;

- (void)insertObject:(ServiceWorker *)w inServiceWorkerArrayAtIndex:(NSUInteger)index;
- (void)removeObjectFromServiceWorkerArrayAtIndex:(NSUInteger)index;

- (void)addObjectToServiceWorkerArray:(ServiceWorker *)worker;
- (void)removeObjectFromServiceWorkerArray:(ServiceWorker *)worker;

- (void)delayedShowWindow;
- (void)hideWindow;

@end
