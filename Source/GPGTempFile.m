//
//  GPGTempFile.m
//  GPGServices
//
//  Created by Chris Fraire on 5/21/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "GPGTempFile.h"

static const int kInvalidDescriptor = -1;

@implementation GPGTempFile

@synthesize fileName = _filename;
@synthesize fileDescriptor = _fd;
@synthesize shouldDeleteFileOnDealloc = _shouldDeleteOnDealloc;

- (void)dealloc 
{
    if (_shouldDeleteOnDealloc && !_didDeleteFile)
        [self deleteFile];
    [_filename release];
    [super dealloc];
}

+ (id)tempFileForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error {
    return [[[self alloc] initForTemplate:template suffixLen:suffixLength error:error] autorelease];
}

- (id)initForTemplate:(NSString *)template suffixLen:(NSUInteger)suffixLength error:(NSError **)error 
{
    if (self = [super init]) {
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        
        // converting the template to writeable UTF8 for the libc functions
        const char *utfRoTemplate = [fileMgr fileSystemRepresentationWithPath:template];
        size_t utfLength = strlen(utfRoTemplate);

        char utfTemplate[utfLength + 1];
        strncpy(utfTemplate, utfRoTemplate, utfLength);
        utfTemplate[utfLength] = '\0';

        // convert the suffix as well to get a computed suffix length
        int utfSuffixLength = 0;
        if (suffixLength > 0) {
            NSString *suffix = [template substringFromIndex:[template length] - suffixLength];
            const char *utfSuffix = [fileMgr fileSystemRepresentationWithPath:suffix];
            utfSuffixLength = strlen(utfSuffix);
        }

        _fd = mkstemps(utfTemplate, utfSuffixLength);
        if (_fd == kInvalidDescriptor) {
            if (error)
                *error = [NSError errorWithDomain:@"libc" code:errno userInfo:nil];
            _didDeleteFile = YES; // treat as already gone
        }
        else {
            _filename = [[[NSFileManager defaultManager] 
                          stringWithFileSystemRepresentation:utfTemplate length:utfLength] retain];
        }

        _shouldDeleteOnDealloc = YES;
    }

    return self;
}

- (void)deleteFile 
{
    [self closeFile];

    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_filename error:&error];
    if (error == nil)
        _didDeleteFile = YES;
}

- (void)closeFile 
{
    if (_fd != kInvalidDescriptor)
    {
        close(_fd);
        _fd = kInvalidDescriptor;
    }    
}

@end
