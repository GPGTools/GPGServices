#import "GPGScripting.h"
#import <Sparkle/Sparkle.h>

@implementation GPGCheckForUpdatesCommand

- (id)performDefaultImplementation {
	SUUpdater *updater = [SUUpdater sharedUpdater];
	[updater performSelectorOnMainThread:@selector(checkForUpdates:) withObject:nil waitUntilDone:NO];
	return nil;
}

@end
