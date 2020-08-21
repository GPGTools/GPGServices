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




- (void)showWindow:(id)sender {
    [self performSelectorOnMainThread:@selector(showWindowOnMain:)
						   withObject:sender
                        waitUntilDone:NO];
}
- (void)showWindowOnMain:(id)sender {
	[self adjustTableColumns];
	
	if (NSScroller.preferredScrollerStyle == NSScrollerStyleOverlay) {
		// Hide the scroll indicator, when the user scrolls down.
		NSClipView *contentView = self.scrollView.contentView;
		contentView.postsBoundsChangedNotifications = YES;
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(boundsDidChange:) name:NSViewBoundsDidChangeNotification object:contentView];
	} else {
		[_scrollIndicator removeFromSuperview];
		_scrollIndicator = nil;
	}

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
	[self adjustTableColumns];
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
		NSString *file = result[@"file"];
		if (file) {
			[urls addObject:[NSURL fileURLWithPath:file]];
		}
	}
	if (urls.count > 0) {
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:urls];
	}
	[self okClicked:sender];
}




- (void)boundsDidChange:(NSNotification *)notification {
	// Hide the scroll indicator, when the user scrolls down.
	NSClipView *contentView = self.scrollView.contentView;
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewBoundsDidChangeNotification object:contentView];
	[_scrollIndicator removeFromSuperview];
	_scrollIndicator = nil;
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
	// Hide the scroll indicator, when the window is resized enough.
	if (_scrollIndicator) {
		CGFloat oldHeight = sender.frame.size.height;
		CGFloat newHeight = frameSize.height;

		if (newHeight > oldHeight) {
			if (self.scrollView.contentView.frame.size.height + newHeight - oldHeight + 30 >= tableView.frame.size.height) {
				[_scrollIndicator removeFromSuperview];
				_scrollIndicator = nil;
			}
		}
	}

	return frameSize;
}

- (void)adjustTableColumns {
	[tableView reloadData];
	NSInteger filenameColumn = [tableView columnWithIdentifier:@"filename"];
	NSInteger resultColumn = [tableView columnWithIdentifier:@"result"];

	NSInteger minWidth = -1;
	NSUInteger count = tableView.numberOfRows;
	if (count == 0) {
		return;
	}
	
	for (NSUInteger row = 0; row < count; row++) {
		NSTableCellView *cellView = [tableView viewAtColumn:filenameColumn row:row makeIfNecessary:YES];
		if (cellView) {
			// The filename column should show the whole filename.
			minWidth = MAX(cellView.textField.intrinsicContentSize.width, minWidth);
		}
		
		cellView = [tableView viewAtColumn:resultColumn row:row makeIfNecessary:YES];
		if (cellView) {
			// The scroll view should not (horizontally) truncate the results
			NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self.scrollView
																		  attribute:NSLayoutAttributeTrailing
																		  relatedBy:NSLayoutRelationGreaterThanOrEqual
																			 toItem:cellView
																		  attribute:NSLayoutAttributeTrailing
																		 multiplier:1
																		   constant:16];
			[self.window.contentView addConstraint:constraint];
		}
	}
	
	if (minWidth > -1) {
		tableView.tableColumns[filenameColumn].width = minWidth + 5;
		[tableView sizeLastColumnToFit];
	}
	
	
	const NSUInteger minVisibleRows = 3; // How many results to show without need to scroll down.
	NSUInteger row = MIN(count - 1, minVisibleRows - 1);
	NSTableCellView *cellView = [tableView viewAtColumn:resultColumn row:row makeIfNecessary:YES];
	if (cellView) {
		// The scroll view should show atleast "minVisibleRows" results.
		NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:self.scrollView
																	  attribute:NSLayoutAttributeBottom
																	  relatedBy:NSLayoutRelationGreaterThanOrEqual
																		 toItem:cellView
																	  attribute:NSLayoutAttributeBottom
																	 multiplier:1
																	   constant:10];
		
		[self.window.contentView addConstraint:constraint];
	}
	
	
	if (count > minVisibleRows) {
		_scrollIndicator.hidden = NO;
	}

}


@end
