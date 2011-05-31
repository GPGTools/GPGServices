//
//  VerificationResultsController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 10.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "FileVerificationController.h"
//#import "MacGPGME/MacGPGME.h"
#import "Libmacgpg/Libmacgpg.h"

#import "FileVerificationDataSource.h"

@implementation FileVerificationController

@synthesize filesToVerify, verificationQueue;

/*
- (id)init {
    self = [super initWithWindowNibName:@"VerificationResultsWindow"];
    
    verificationQueue = [[NSOperationQueue alloc] init];
    [verificationQueue addObserver:self 
                        forKeyPath:@"operationCount" 
                           options:NSKeyValueObservingOptionNew 
                           context:NULL];
    
    filesInVerification = [[NSMutableSet alloc] init];
    
    return self;
}

- (void)dealloc {
    [verificationQueue waitUntilAllOperationsAreFinished];
    [verificationQueue release];
    [filesInVerification release];
    
    [super dealloc];
}

- (void)windowDidLoad {
    [tableView setDoubleAction:@selector(doubleClickAction:)];
	[tableView setTarget:self];
}

- (NSInteger)runModal {
    [NSApp activateIgnoringOtherApps:YES];
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
        
        if(signatureFile != nil) {
            if([filesInVerification containsObject:signatureFile]) {
                continue;
            } else {
                //Propably a problem with restarting of validation when files are missing
                [filesInVerification addObject:signatureFile];
            }
        }
        
        [verificationQueue addOperationWithBlock:^(void) {
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
            
            NSException* firstException = nil;
            NSException* secondException = nil;
            
            NSArray* sigs = nil;
          
            if([fmgr fileExistsAtPath:signedFile] && [fmgr fileExistsAtPath:signatureFile]) {
                @try {
                    GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
                    GPGData* fileData = [[[GPGData alloc] initWithContentsOfFile:signatureFile] autorelease];
                    GPGData* signedData = [[[GPGData alloc] initWithContentsOfFile:signedFile] 
                                           autorelease];
                    sigs = [ctx verifySignatureData:fileData againstData:signedData];
                } @catch (NSException *exception) {
                    firstException = exception;
                    sigs = nil;
                }
            }
            
            //Try to verify the file itself without a detached sig
            if(sigs == nil || sigs.count == 0) {
                @try {
                    GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
                    GPGData* serviceData = [[[GPGData alloc] initWithContentsOfFile:serviceFile] autorelease];
                    sigs = [ctx verifySignedData:serviceData];
                } @catch (NSException *exception) {
                    secondException = exception;
                    sigs = nil;
                }
            }
            
            if(sigs != nil) {
                if(sigs.count == 0) {
                    id verificationResult = nil; //NSString or NSAttributedString
                    verificationResult = @"Verification FAILED: No signatures found";
                    
                    NSColor* bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                    
                    NSRange range = [verificationResult rangeOfString:@"FAILED"];
                    verificationResult = [[NSMutableAttributedString alloc] 
                                          initWithString:verificationResult];
                    
                    [verificationResult addAttribute:NSFontAttributeName 
                                               value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                                               range:range];
                    [verificationResult addAttribute:NSBackgroundColorAttributeName 
                                               value:bgColor
                                               range:range];
                    
                    NSDictionary* result = [NSDictionary dictionaryWithObjectsAndKeys:
                                            [signedFile lastPathComponent], @"filename",
                                            verificationResult, @"verificationResult", 
                                            nil];
                    
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^(void) {
                        [dataSource addResults:result];
                    }];
                } else if(sigs.count > 0) {
                    for(GPGSignature* sig in sigs) {
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^(void) {
                            [dataSource addResultFromSig:sig forFile:signedFile];
                        }];
                    }
                }         
            } else {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^(void) {
                    [dataSource addResults:[NSDictionary dictionaryWithObjectsAndKeys:
                                            [signedFile lastPathComponent], @"filename",
                                            @"No verifiable data found", @"verificationResult",
                                            nil]]; 
                }];
            }
            
            [pool release];
        }];
    }
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
*/

@end
