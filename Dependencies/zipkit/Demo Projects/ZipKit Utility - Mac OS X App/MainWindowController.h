#import <Cocoa/Cocoa.h>

@interface MainWindowController : NSWindowController {
@private
	NSString *message;
	NSString *action;
	NSDate *startTime;
	double progress;
	NSTimeInterval remainingTime;
	unsigned long long sizeWritten;
	unsigned long long totalSize;
	unsigned long long totalCount;
	BOOL isIndeterminate;
	NSOperationQueue *zipQueue;
}

- (IBAction) open:(id)sender;
- (IBAction) cancel:(id)sender;

@property (copy) NSString *message;
@property (copy) NSString *action;
@property (retain) NSDate *startTime;
@property (assign) double progress;
@property (assign) NSTimeInterval remainingTime;
@property (assign) unsigned long long sizeWritten;
@property (assign) unsigned long long totalSize;
@property (assign) unsigned long long totalCount;
@property (assign) BOOL isIndeterminate;
@property (retain) NSOperationQueue *zipQueue;

@end