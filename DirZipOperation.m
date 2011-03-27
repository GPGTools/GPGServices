//
//  DirZipOperation.m
//  GPGServices
//
//  Created by Moritz Ulrich on 27.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DirZipOperation.h"

#import "ZipKit/ZKDataArchive.h"

@implementation DirZipOperation

@synthesize filePath, delegate;

- (NSData*)zipData {
    return [archive data];
}

- (id)init {
    self = [super init];
    archive = [[ZKDataArchive alloc] init];
    return self;
}

- (void)dealloc {
    [archive release];
    [super dealloc];
}

- (void)main {
    [archive deflateDirectory:self.filePath 
               relativeToPath:[self.filePath stringByDeletingLastPathComponent] 
            usingResourceFork:YES];
    
    NSLog(@"made zip data with size: %i", [[archive data] length]);
}

@end
