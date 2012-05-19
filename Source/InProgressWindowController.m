//
//  InProgressWindowController.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "InProgressWindowController.h"
#import "WorkerProgressViewItem.h"

static const NSTimeInterval kShowWindowDelaySeconds = 1;
static const CGFloat kSubviewHeight = 64.;
static const NSUInteger kMaxVisibleItems = 4;

@interface InProgressWindowController ()
- (void)showWindowCallback:(id)sender;
- (void)adjustWindowSize;
- (CGFloat)windowTitleBarHeight;
@end

@implementation InProgressWindowController

@synthesize collectionView = _collectionView;
@synthesize arrayController = _arrayController;
@synthesize serviceWorkerArray = _serviceWorkerArray;

- (void)dealloc
{
    [_serviceWorkerArray release];
    [_delayTimer release];
    [super dealloc];
}

- (id)init
{
    if (self = [super initWithWindowNibName:@"InProgressWindow"]) {
        self.serviceWorkerArray = [NSMutableArray array];
    }
    return self;
}

- (void)insertObject:(ServiceWorker *)w inServiceWorkerArrayAtIndex:(NSUInteger)index {
    [_serviceWorkerArray insertObject:w atIndex:index];
    [self adjustWindowSize];
}

- (void)removeObjectFromServiceWorkerArrayAtIndex:(NSUInteger)index {
    [_serviceWorkerArray removeObjectAtIndex:index];
    [self adjustWindowSize];
}

- (void)addObjectToServiceWorkerArray:(id)worker {
    [self insertObject:worker inServiceWorkerArrayAtIndex:[_serviceWorkerArray count]];
}

- (void)removeObjectFromServiceWorkerArray:(id)worker {
    NSUInteger x = [_serviceWorkerArray indexOfObject:worker];
    if (x != NSNotFound)
        [self removeObjectFromServiceWorkerArrayAtIndex:x];
}

- (void)delayedShowWindow
{
    if (!_delayTimer)
    {
        _delayTimer = [[NSTimer timerWithTimeInterval:kShowWindowDelaySeconds 
                                               target:self 
                                             selector:@selector(showWindowCallback:)
                                             userInfo:nil repeats:NO] retain];
        [[NSRunLoop currentRunLoop] addTimer:_delayTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)showWindowCallback:(id)sender
{
    [_delayTimer release];
    _delayTimer = nil;
    [self showWindow:nil];
}

- (void)hideWindow
{
    if (_delayTimer) {
        [_delayTimer invalidate];
        [_delayTimer release];
        _delayTimer = nil;
    }
    [self.window orderOut:nil];
}

- (void)adjustWindowSize
{
    NSUInteger nitems = [_serviceWorkerArray count];
    NSUInteger ndisplay = (nitems > kMaxVisibleItems) ? kMaxVisibleItems : nitems;
    ndisplay = MAX(ndisplay, 1);
    CGFloat newHeight = ndisplay * kSubviewHeight + [self windowTitleBarHeight];

    NSRect origFrame = self.window.frame;
    NSRect newFrame = NSMakeRect(origFrame.origin.x, origFrame.origin.y, 
                                 origFrame.size.width, newHeight);
    [self.window setFrame:newFrame display:YES animate:YES];
}

- (CGFloat)windowTitleBarHeight
{
    NSRect frame = NSMakeRect (0, 0, 100, 100);    
    NSRect contentRect;
    contentRect = [NSWindow contentRectForFrameRect: frame
                                          styleMask: NSTitledWindowMask];    
    return (frame.size.height - contentRect.size.height);
} 

@end
