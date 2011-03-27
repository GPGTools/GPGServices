#import "ZipFileOperation.h"
#import <ZipKit/ZKFileArchive.h>
#import <ZipKit/ZKLog.h>

@implementation ZipFileOperation

- (void) main {
	[ZKFileArchive process:self.item usingResourceFork:YES withInvoker:self andDelegate:self.delegate];
}

@synthesize item, delegate;

@end