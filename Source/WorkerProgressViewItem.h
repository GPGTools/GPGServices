//
//  WorkerProgressViewItem.h
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface WorkerProgressViewItem : NSCollectionViewItem {
    NSProgressIndicator *_progressIndicator;
}

@property (readonly, nonatomic) BOOL shouldAnimate;

- (IBAction)cancelTouched:(id)sender;

@end
