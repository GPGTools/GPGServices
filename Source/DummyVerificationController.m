//
//  FileVerificationDummyController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DummyVerificationController.h"
#import "FileVerificationDataSource.h"
#import "GPGServices.h"

@interface DummyVerificationController (ThreadSafety)

- (void)showWindowOnMain:(id)sender;
- (void)runModalOnMain:(NSMutableArray *)resHolder;

@end

@implementation DummyVerificationController


+ (instancetype)verificationController {
	return [[self alloc] initWithWindowNibName:@"VerificationResultsWindow"]; // thread-safe
}


- (id)initWithWindowNibName:(NSString *)windowNibName {
	// Call super -initWithWindowNibName: only on the main thread.
	
	__block DummyVerificationController *newSelf = self;
	void (^block)(void) = ^{
		newSelf = [super initWithWindowNibName:windowNibName];
		[newSelf window]; // Load the window.
	};
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
        
    return newSelf;
}


- (void)awakeFromNib {
	[super awakeFromNib];
}
- (void)dealloc {
	
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
}





- (void)showWindow:(id)sender {
    [self performSelectorOnMainThread:@selector(showWindowOnMain:)
						   withObject:sender
                        waitUntilDone:NO];
}
- (void)showWindowOnMain:(id)sender {
	
	[_scrollView flashScrollers];
	
    [super showWindow:sender];
	[NSApp activateIgnoringOtherApps:YES];
	
	if (!_terminateCanceled) {
		_terminateCanceled = YES;
		GPGServices *gpgServices = NSApp.delegate;
		[gpgServices cancelTerminateTimer];
		_selfRetain = self;
	}
}


- (void)addResults:(NSArray<NSDictionary *> *)results {
    [self performSelectorOnMainThread:@selector(addResultsOnMain:)
						   withObject:results
						waitUntilDone:NO];
}
- (void)addResultsOnMain:(NSArray<NSDictionary *> *)results {
	[dataSource addResults:results];
	[self showWindowOnMain:nil];
}


- (IBAction)okClicked:(id)sender {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self.window close];
	if (_terminateCanceled) {
		_terminateCanceled = NO;
		GPGServices *gpgServices = NSApp.delegate;
		[gpgServices goneIn60Seconds];
		_selfRetain = nil;
	}
}

- (IBAction)showInFinder:(id)sender {
	NSArray<NSDictionary *> *results = dataSource.verificationResults;
	NSMutableArray *urls = [NSMutableArray new];
	for (NSDictionary *result in results) {
		NSString *file = result[RESULT_FILE_KEY];
		if (file) {
			[urls addObject:[NSURL fileURLWithPath:file]];
		}
	}
	if (urls.count > 0) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:urls];
	}
	[self okClicked:sender];
}




@end
