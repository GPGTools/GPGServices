//
//  GPGTempFile.h
//  GPGServices
//
//  Created by Chris Fraire on 5/21/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GPGTempFile : NSObject {
    NSString *_filename;
    int _fd;
    BOOL _shouldDeleteOnDealloc;
    BOOL _didDeleteFile;
}

// initialize a temp file using mkstemp
+ (id)tempFileForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error;
- (id)initForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error;

// if successfully initialized, will be a non-nil file name
@property (readonly) NSString *fileName;

// if successfully initialized, will be a valid, open descriptor; otherwise -1;
// after closeFile or deleteFile is called, will be -1
@property (readonly) int fileDescriptor;

// default is YES
@property (assign) BOOL shouldDeleteFileOnDealloc;

- (void)deleteFile;
- (void)closeFile;

@end
