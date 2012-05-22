//
//  GPGTempFile.m
//  GPGServices
//
//  Created by Chris Fraire on 5/21/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "GPGTempFile.h"

@implementation GPGTempFile

@synthesize fileName = _filename;
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
        // converting the template to writeable UTF8 for the libc functions
        const char *utfRoTemplate = [template UTF8String];
        size_t utfLength = strlen(utfRoTemplate);

        char utfTemplate[utfLength + 1];
        strncpy(utfTemplate, utfRoTemplate, utfLength);
        utfTemplate[utfLength] = '\0';

        // convert the suffix as well to get a computed suffix length
        int utfSuffixLength = 0;
        if (suffixLength > 0) {
            NSString *suffix = [template substringFromIndex:[template length] - suffixLength];
            const char *utfSuffix = [suffix UTF8String];
            utfSuffixLength = strlen(utfSuffix);
        }
        
        int rc = mkstemps(utfTemplate, utfSuffixLength);
        if (rc == -1) {
            if (error)
                *error = [NSError errorWithDomain:@"libc" code:rc userInfo:nil];
            _didDeleteFile = YES; // treat as already gone
        }
        else {
            _filename = [[NSString stringWithUTF8String:utfTemplate] retain];
        }

        _shouldDeleteOnDealloc = YES;
    }

    return self;
}

- (void)deleteFile 
{
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_filename error:&error];
    if (error == nil)
        _didDeleteFile = YES;
}

@end
