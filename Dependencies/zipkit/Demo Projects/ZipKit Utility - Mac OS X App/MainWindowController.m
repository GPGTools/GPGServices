#import "MainWindowController.h"
#import "ZipFileOperation.h"
#import "RemainingTimeTransformer.h"
#import <ZipKit/ZKFileArchive.h>
#import <ZipKit/ZKDataArchive.h>
#import <ZipKit/ZKLog.h>
#import <ZipKit/ZKDefs.h>
#import <ZipKit/NSFileManager+ZKAdditions.h>

const double maxProgress = 100.0;

@implementation MainWindowController

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename {
	if ([[self.zipQueue operations] count] < 1) {
		ZipFileOperation *zipOp = [ZipFileOperation new];
		zipOp.item = filename;
		zipOp.delegate = self;
		[self.zipQueue addOperation:zipOp];
		return YES;
	} else
		return NO;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
	[self showWindow:self];
	return NO; 
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
	[ZKLog sharedInstance].minimumLevel = [[NSUserDefaults standardUserDefaults] integerForKey:ZKLogLevelKey];
	self.message = NSLocalizedString(@"Ready", @"status message");
	self.progress = 0.0;
	self.remainingTime = 0.0;
	self.zipQueue = [NSOperationQueue new];
	[self.zipQueue setMaxConcurrentOperationCount:1];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	if ([[self.zipQueue operations] count] > 0) {
		NSBeginAlertSheet(NSLocalizedString(@"Please cancel before quitting", @"alert title"),
						  NSLocalizedString(@"OK", @"button label"), nil, nil, self.window, self,
						  nil, nil, nil,
						  NSLocalizedString(@"An action is in progress. Cancel it before quitting the application.", @"alert message"));
		return NSTerminateCancel;
	} else
		return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)n {
	[self.zipQueue cancelAllOperations];
}

+ (void) initialize {
	[NSValueTransformer setValueTransformer:[RemainingTimeTransformer new] forName:@"RemainingTimeTransformer"];
	[[NSUserDefaults standardUserDefaults] registerDefaults:
	 [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInteger:ZKLogLevelError] forKey:ZKLogLevelKey]];
	[super initialize];
}

- (IBAction) open:(id)sender {
	[self showWindow:self];
	if ([[self.zipQueue operations] count] < 1) {
		NSOpenPanel *panel = [NSOpenPanel openPanel];
		[panel setCanChooseDirectories:YES];
		[panel setAllowsMultipleSelection:YES];
		[panel setCanChooseFiles:YES];
		[panel setResolvesAliases:NO];
		if ([panel runModalForTypes:nil] == NSOKButton) {
			NSArray *filenames = [panel filenames];
			@try {				
				NSString *firstFilename = [filenames objectAtIndex:0];
				
				ZipFileOperation *zipFileOperation = [ZipFileOperation new];
				zipFileOperation.item = ([filenames count] == 1) ? (id)firstFilename : filenames;
				zipFileOperation.delegate = self;
				[self.zipQueue addOperation:zipFileOperation];
				
//				if ([filenames count] == 1 && [[firstFilename pathExtension] isEqualToString:ZKArchiveFileExtension]) {
//					NSString *archivePath = firstFilename;
//					ZKDataArchive *archive = [ZKDataArchive archiveWithArchivePath:archivePath];
//					[archive inflateInFolder:[archivePath stringByDeletingLastPathComponent]
//							  withFolderName:[[archivePath lastPathComponent] stringByDeletingPathExtension]
//						   usingResourceFork:YES];
//				}
			}
			@catch (NSException *e) {
				ZKLogWithException(e);
			}
		}
	}
}

- (IBAction) cancel:(id)sender {
	if ([[self.zipQueue operations] count] < 1)
		return;
	NSBeginAlertSheet(NSLocalizedString(@"Are you sure you want to cancel?", @"alert title"),
					  NSLocalizedString(@"Yes", @"button label"), NSLocalizedString(@"No", @"button label"), nil, self.window, self,
					  @selector(sheetDidEnd:returnCode:contextInfo:), nil, nil,
					  NSLocalizedString(@"An action is in progress.", @"alert message"));
}
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	if (returnCode == NSOKButton) {
		[self.zipQueue cancelAllOperations];
	}
}

#pragma mark -
#pragma mark Delegate Methods

- (void) onZKArchiveDidBeginZip:(ZKArchive *) archive {
	self.isIndeterminate = YES;
	self.progress = 0.0;
	self.remainingTime = NSTimeIntervalSince1970;
	self.action = NSLocalizedString(@"Archiving", @"action for status message");
	self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ items (%@)...", @"status message"),
					self.action, [[archive archivePath] lastPathComponent]];
	self.startTime = [NSDate date];
	[self showWindow:self];
	ZKLogDebug(self.message);
}

- (void) onZKArchiveDidBeginUnzip:(ZKArchive *) archive {
	self.isIndeterminate = YES;
	self.progress = 0.0;
	self.remainingTime = NSTimeIntervalSince1970;
	self.message = @"";
	self.action = NSLocalizedString(@"Extracting", @"action for status message");
	self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ items (%@)...", @"status message"),
					self.action, [[archive archivePath] lastPathComponent]];
	self.startTime = [NSDate date];
	[self showWindow:self];
	ZKLogDebug(self.message);
}

- (void) onZKArchiveDidEndZip:(ZKArchive *) archive {
	self.progress = maxProgress;
	self.remainingTime = 0.0;
	self.isIndeterminate = NO;
	self.message = [NSString stringWithFormat:NSLocalizedString(@"Archive created (%@)", @"status message"),
					[[archive archivePath] lastPathComponent]];
	ZKLogDebug(self.message);
}

- (void) onZKArchiveDidEndUnzip:(ZKArchive *) archive {
	self.progress = maxProgress;
	self.remainingTime = 0.0;
	self.isIndeterminate = NO;
	self.message = [NSString stringWithFormat:NSLocalizedString(@"Archive extracted (%@)", @"status message"),
					[[archive archivePath] lastPathComponent]];
	ZKLogDebug(self.message);
}

- (void) onZKArchiveDidCancel:(ZKArchive *) archive {
	self.progress = 0.0;
	self.remainingTime = 0.0;
	self.isIndeterminate = NO;
	self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ cancelled", @"status message"), self.action];
	ZKLogDebug(self.message);
}

- (void) onZKArchiveDidFail:(ZKArchive *) archive {
	self.progress = 0.0;
	self.remainingTime = 0.0;
	self.isIndeterminate = NO;
	self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ failed", @"status message"), self.action];
	ZKLogError(self.message);
}

- (void) onZKArchive:(ZKArchive *) archive didUpdateTotalSize:(unsigned long long)size {
	self.totalSize = size;
}

- (void) onZKArchive:(ZKArchive *) archive didUpdateTotalCount:(unsigned long long)count {
	self.totalCount = count;
	if (self.totalCount < 1)
		self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ items (%@)...", @"status message"),
						self.action, [[archive archivePath] lastPathComponent]];
	else if (self.totalCount == 1)
		self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ 1 item (%@)...", @"status message"),
						self.action, [[archive archivePath] lastPathComponent]];
	else
		self.message = [NSString stringWithFormat:NSLocalizedString(@"%@ %qu items (%@)...", @"status message"),
						self.action, self.totalCount, [[archive archivePath] lastPathComponent]];
}

- (void) onZKArchive:(ZKArchive *) archive didUpdateBytesWritten:(unsigned long long)byteCount {
	self.sizeWritten += byteCount;
	self.isIndeterminate = (self.totalSize == 0);
	if (self.totalSize > 0)
		self.progress = maxProgress * ((double)self.sizeWritten) / ((double)self.totalSize);
	
	NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.startTime];
	NSTimeInterval rt = (100.0 * elapsed / self.progress) - elapsed;
	if (rt < self.remainingTime)
		self.remainingTime = rt;
}

- (void) onZKArchive:(ZKArchive *) archive willZipPath:(NSString *)path {
	ZKLogDebug(@"Adding %@...", [path lastPathComponent]);
}

- (void) onZKArchive:(ZKArchive *) archive willUnzipPath:(NSString *)path {
	ZKLogDebug(@"Extracting %@...", [path lastPathComponent]);
}

- (BOOL) zkDelegateWantsSizes {
	return YES;
}

@synthesize message, action, remainingTime, startTime, progress, sizeWritten, totalSize, totalCount, isIndeterminate, zipQueue;

@end