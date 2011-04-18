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
    filesInVerification = [[NSMutableSet alloc] init];
    
    return self;
}

- (void)dealloc {
    [verificationQueue waitUntilAllOperationsAreFinished];
    [verificationQueue release];
    [verificationResults release];
    [filesInVerification release];
    
    [super dealloc];
}

- (void)windowDidLoad {
    [tableView setDoubleAction:@selector(doubleClickAction:)];
	[tableView setTarget:self];
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
        
        //Do the file stuff here to be able to check if file is already in verification
        NSString* signatureFile = serviceFile;
        NSString* signedFile = [self searchFileForSignatureFile:signatureFile];
        if(signedFile == nil) {
            NSString* tmp = [self searchSignatureFileForFile:signatureFile];
            signedFile = signatureFile;
            signatureFile = tmp;
        }
        
        if([filesInVerification containsObject:signatureFile]) {
            continue;
        } else {
            //Propably a problem with restarting of validation when files are missing
            [filesInVerification addObject:signatureFile];
        }
        
        [verificationQueue addOperationWithBlock:^(void) {
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
            
            NSColor* bgColor = nil;
            NSString* verificationResult = nil;
            BOOL verified = NO;
            
            NSException* firstException = nil;
            NSException* secondException = nil;
            
            NSArray* sigs = nil;

            //TODO: Provide way for user to choose file
            if([fmgr fileExistsAtPath:signatureFile] == NO) {
                NSLog(@"file not found: %@", signatureFile);
                return;
            }
            
            if([fmgr fileExistsAtPath:signedFile] == NO) {
                NSLog(@"file not found: %@", signedFile);
                return;
            }
            
            
            GPGData* fileData = [[[GPGData alloc] initWithContentsOfFile:signatureFile] autorelease];
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
                          [signedFile lastPathComponent], @"filename",
                          signatureFile, @"signaturePath",
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

- (void)doubleClickAction:(id)sender {
	
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
