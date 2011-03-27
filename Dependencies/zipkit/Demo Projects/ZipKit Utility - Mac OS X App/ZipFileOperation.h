#import <Foundation/Foundation.h>

@interface ZipFileOperation : NSOperation {
	id item;
	id delegate;
}

@property (assign) id item;
@property (assign) id delegate;

@end