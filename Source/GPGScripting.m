#import "GPGScripting.h"

@implementation GPGCheckForUpdatesCommand

- (id)performDefaultImplementation {
	NSRunAlertPanel(@"This version does not support automatic updates.",
					@"Please go to https://old.gpgtools.org and look for the current version.", nil, nil, nil);
	return nil;
}

@end
