//
//  GPGSAlert.m
//  GPGServices
//
//  Created by Mento on 06.04.20.
//

#import "GPGSAlert.h"
#import "GPGServices.h"

@interface GPGSAlert () <NSWindowDelegate> {
	__strong GPGSAlert *_selfRetain;
}
@end

@implementation GPGSAlert

- (instancetype)init {
	self = [super initWithWindowNibName:@"GPGSAlert"];
	return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
}

- (void)showWindow:(id)sender {
	_selfRetain = self;
	if (!self.window.isVisible) {
		GPGServices *gpgServices = NSApp.delegate;
		[gpgServices cancelTerminateTimer];
	}
	[super showWindow:sender];
}

- (void)show {
	[self showWindow:nil];
}

- (IBAction)dismissController:(id)sender {
	[self.window close];
	[super dismissController:sender];
	GPGServices *gpgServices = NSApp.delegate;
	[gpgServices goneIn60Seconds];
	_selfRetain = nil;
}

- (IBAction)showFilesInFinder:(id)sender {
	NSArray *theFiles = self.files;
	
	if ([theFiles isKindOfClass:[NSArray class]] && theFiles.count > 0) {
		NSMutableArray *urls = [NSMutableArray new];
		for (NSString *file in theFiles) {
			[urls addObject:[NSURL fileURLWithPath:file]];
		}
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:urls];
	}
	
	[self dismissController:sender];
}



@end
