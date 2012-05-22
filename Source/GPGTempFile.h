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
    BOOL _shouldDeleteOnDealloc;
    BOOL _didDeleteFile;
}

// initialize a temp file using mkstemp
+ (id)tempFileForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error;
- (id)initForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error;

@property (readonly) NSString *fileName;

// default is YES
@property (assign) BOOL shouldDeleteFileOnDealloc;

- (void)deleteFile;

@end
