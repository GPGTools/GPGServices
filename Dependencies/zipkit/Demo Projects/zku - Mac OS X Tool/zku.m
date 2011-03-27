#import <Foundation/Foundation.h>
#import "ZKFileArchive.h"
#import "ZKLog.h"
#include <objc/objc-auto.h>

@interface ZKUController : NSObject
- (void) process:(NSArray *)items;
@end
@implementation ZKUController : NSObject

- (void) process:(NSArray *)items {
	[ZKFileArchive process:items usingResourceFork:YES withInvoker:nil andDelegate:self];
}

- (void) onZKArchiveDidBeginZip:(ZKArchive *) archive {
	ZKLogNotice(@"Creating archive %@", [archive.archivePath lastPathComponent]);
}

- (void) onZKArchiveDidBeginUnzip:(ZKArchive *) archive {
	ZKLogNotice(@"Extracting from archive %@", [archive.archivePath lastPathComponent]);
}

- (void) onZKArchiveDidEndZip:(ZKArchive *) archive {
	ZKLogNotice(@"%@ created", [archive.archivePath lastPathComponent]);
}

- (void) onZKArchiveDidEndUnzip:(ZKArchive *) archive {
	ZKLogNotice(@"%@ extracted", [archive.archivePath lastPathComponent]);
}

- (void) onZKArchiveDidFail:(ZKArchive *) archive {
	ZKLogError(@"Archiving failed!");
}

- (void) onZKArchive:(ZKArchive *) archive willZipPath:(NSString *)path {
	ZKLogNotice(@"...adding %@", [path lastPathComponent]);
}

- (void) onZKArchive:(ZKArchive *) archive willUnzipPath:(NSString *)path {
	ZKLogNotice(@"...extracting %@", [path lastPathComponent]);
}

- (BOOL) zkDelegateWantsSizes {
	return NO;
}

@end

int main(int argc, const char * argv[]) {
	objc_startCollectorThread();
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	[ZKLog sharedInstance].minimumLevel = ZKLogLevelAll;
	
	if (argc > 1) {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSMutableArray *items = [NSMutableArray arrayWithCapacity:(argc - 1)];
		for (NSUInteger i = 1; i <= argc; i++) {
			const char *p = argv[i];
			if (p != NULL) {
				NSString *path = [NSString stringWithUTF8String:p];
				if ([fileManager fileExistsAtPath:path])
					[items addObject:path];
			}
		}
		if ([items count] > 0)
			[[[ZKUController alloc] init] process:items];
	} else
		ZKLogDebug(@"Nothing to process");
	
	[pool drain];
	return EXIT_SUCCESS;
}