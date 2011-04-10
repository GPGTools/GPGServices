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

@synthesize filesToVerify, queueIsActive, verificationQueue, verificationResults;

- (id)init {
    self = [super initWithWindowNibName:@"VerificationResultsWindow"];
 
    verificationQueue = [[NSOperationQueue alloc] init];
    queueIsActive = NO;
    verificationResults = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)dealloc {
    [verificationQueue waitUntilAllOperationsAreFinished];
    [verificationQueue release];
    [verificationResults release];
    
    [super dealloc];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
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
    [self willChangeValueForKey:@"queueIsActive"];
    queueIsActive = YES;
    [self didChangeValueForKey:@"queueIsActive"];
    
    NSColor* bgColor = nil;
    NSString* verificationResult = nil;
    BOOL verified = NO;
    
    GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
    
    for(NSString* file in self.filesToVerify) {
        [verificationQueue addOperationWithBlock:^(void) {
            GPGData* fileData = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
            
            NSException* firstException = nil;
            NSException* secondException = nil;
            
            NSArray* sigs = nil;
            NSString* signedFile = [self searchFileForSignatureFile:file];
            if(signedFile != nil) {
                @try {
                    GPGData* signedData = [[[GPGData alloc] initWithContentsOfFile:signedFile] 
                                           autorelease];
                    sigs = [ctx verifySignatureData:fileData againstData:signedData];
                }
                @catch (NSException *exception) {
                    firstException = exception;
                    sigs = nil;
                }
            }
            //Try to verify the file itself without a detached sig
            if(sigs == nil) {
                @try {
                    sigs = [ctx verifySignedData:fileData];
                }
                @catch (NSException *exception) {
                    firstException = exception;
                    sigs = nil;
                }
            }
            
            NSColor* color = nil;
            if(verified)
                color = [NSColor greenColor];
            else
                color = [NSColor redColor];
            
            //Add to results
            NSDictionary* results = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [file lastPathComponent], @"filename",
                                     verificationResults, @"verificationResult", 
                                     [NSNumber numberWithBool:verified], @"verificationSucceeded",
                                     color, @"resultColor",
                                     nil];
            [self performSelectorOnMainThread:@selector(addResults:) withObject:results waitUntilDone:YES];
        }];
    }
}

- (void)addResults:(NSDictionary*)results {
    [self willChangeValueForKey:@"verificationResults"];
    [verificationResults addObject:results];
    [self didChangeValueForKey:@"verificationResults"];
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


@end
