//
//  VerificationResultsController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 10.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "FileVerificationController.h"
#import "MacGPGME/MacGPGME.h"

@implementation FileVerificationController

@synthesize filesToVerify, verificationQueue, verificationResults;

- (id)init {
    self = [super initWithWindowNibName:@"VerificationResultsWindow"];
 
    verificationQueue = [[NSOperationQueue alloc] init];
    [verificationQueue addObserver:self 
                        forKeyPath:@"operationCount" 
                           options:NSKeyValueObservingOptionNew 
                           context:NULL];

    verificationResults = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)dealloc {
    [verificationQueue waitUntilAllOperationsAreFinished];
    [verificationQueue release];
    [verificationResults release];
    
    [super dealloc];
}

- (NSInteger)runModal {
	[self showWindow:self];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
	return ret;
}

- (IBAction)okClicked:(id)sender {
	[NSApp stopModalWithCode:0];
}

- (void)startVerification:(void(^)(NSArray*))callback {
    [self window]; //Load window to setup bindings
    
    [indicator startAnimation:self];
        
    for(NSString* serviceFile in self.filesToVerify) {
        [verificationQueue addOperationWithBlock:^(void) {
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
            
            NSString* file = serviceFile;
            
            NSColor* bgColor = nil;
            NSString* verificationResult = nil;
            BOOL verified = NO;
            
            NSException* firstException = nil;
            NSException* secondException = nil;
            
            NSArray* sigs = nil;
            NSString* signedFile = [self searchFileForSignatureFile:file];
            if(signedFile == nil) {
                NSString* tmp = [self searchSignatureFileForFile:file];
                signedFile = file;
                file = tmp;
            }
            
            NSLog(@"file: %@", file);
            NSLog(@"signedFile: %@", signedFile);

            //TODO: Provide way for user to choose file
            if([fmgr fileExistsAtPath:file] == NO) {
                NSLog(@"file not found: %@", file);
                return;
            }
            
            if([fmgr fileExistsAtPath:signedFile] == NO) {
                NSLog(@"file not found: %@", signedFile);
                return;
            }
            
            
            GPGData* fileData = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
            if(signedFile != nil) {
                @try {
                    GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
                    GPGData* signedData = [[[GPGData alloc] initWithContentsOfFile:signedFile] 
                                           autorelease];
                    sigs = [ctx verifySignatureData:fileData againstData:signedData];
                } @catch (NSException *exception) {
                    firstException = exception;
                    sigs = nil;
                }
            }
            //Try to verify the file itself without a detached sig
            if(sigs == nil) {
                @try {
                    GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
                    sigs = [ctx verifySignedData:fileData];
                } @catch (NSException *exception) {
                    secondException = exception;
                    sigs = nil;
                }
            }
            
            
            NSDictionary* result = nil;
            if(sigs != nil) {
                verified = YES;

                if(sigs.count == 0) {
                    verificationResult = @"Verification FAILED: No signature data found.";
                    bgColor = [NSColor redColor];
                } else if(sigs.count > 0) {
                    GPGSignature* sig=[sigs objectAtIndex:0];
                    if(GPGErrorCodeFromError([sig status]) == GPGErrorNoError) {
                        GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
                        NSString* userID = [[ctx keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
                        NSString* validity = [sig validityDescription];
                        
                        verificationResult = [NSString stringWithFormat:@"Signed by: %@ (%@ trust)", userID, validity];
                        bgColor = [NSColor greenColor];
                    } else {
                        verificationResult = [NSString stringWithFormat:@"Verification FAILED: %@", GPGErrorDescription([sig status])];
                        bgColor = [NSColor redColor];
                    }
                }      
                
                //Add to results
                result = [NSDictionary dictionaryWithObjectsAndKeys:
                          [file lastPathComponent], @"filename",
                          file, @"signaturePath",
                          verificationResult, @"verificationResult", 
                          [NSNumber numberWithBool:verified], @"verificationSucceeded",
                          bgColor, @"bgColor",
                          nil];
            }
            
            
            
            if(result != nil)
                [self performSelectorOnMainThread:@selector(addResults:) 
                                       withObject:result
                                    waitUntilDone:YES];
            
            [pool release];
        }];
    }
}

- (void)addResults:(NSDictionary*)results {
    [self willChangeValueForKey:@"verificationResults"];
    [verificationResults addObject:results];
    [self didChangeValueForKey:@"verificationResults"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {    
    if([keyPath isEqualToString:@"operationCount"]) {
        if([object operationCount] == 0) 
            [indicator stopAnimation:self];
    }
}

#pragma mark - Helper Methods

- (NSString*)searchFileForSignatureFile:(NSString*)sigFile {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    NSString* file = [sigFile stringByDeletingPathExtension];
    BOOL isDir = NO;
    if([fmgr fileExistsAtPath:file isDirectory:&isDir] && !isDir)
        return file;
    else
        return nil;
}

- (NSString*)searchSignatureFileForFile:(NSString*)sigFile {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    NSSet* exts = [NSSet setWithObjects:@".sig", @".asc", nil];
    
    for(NSString* ext in exts) {
        NSString* file = [sigFile stringByAppendingString:ext];
        BOOL isDir = NO;
        if([fmgr fileExistsAtPath:file isDirectory:&isDir] && !isDir)
            return file;
    }
    
    return nil;
}


@end
