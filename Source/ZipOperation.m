//
//  DirZipOperation.m
//  GPGServices
//
//  Created by Moritz Ulrich on 27.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ZipOperation.h"

#import "ZipKit/ZKDataArchive.h"

@implementation ZipOperation

@synthesize filePath, files, delegate;

- (NSData*)zipData {
    return [archive data];
}

- (id)init {
    self = [super init];
    archive = [[ZKDataArchive alloc] init];
    return self;
}


- (void)main {
    if(filePath != nil) {
        [archive deflateDirectory:self.filePath 
                   relativeToPath:[self.filePath stringByDeletingLastPathComponent] 
                usingResourceFork:YES];
    } else if(files != nil) {
        [archive deflateFiles:self.files 
               relativeToPath:[[self.files objectAtIndex:0] stringByDeletingLastPathComponent]
            usingResourceFork:YES];
    }
    
    NSLog(@"made zip data with size: %lu", [[archive data] length]);
}

@end
