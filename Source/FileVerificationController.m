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

@interface FileVerificationController ()

- (void)runModalOnMain:(NSMutableArray *)resHolder;

@end

@implementation FileVerificationController

@synthesize filesToVerify, verificationQueue;

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
    NSMutableArray *resHolder = [NSMutableArray arrayWithCapacity:1];
    [self performSelectorOnMainThread:@selector(runModalOnMain:) withObject:resHolder waitUntilDone:YES];
    return [[resHolder lastObject] integerValue];
}

- (void)runModalOnMain:(NSMutableArray *)resHolder {
    [NSApp activateIgnoringOtherApps:YES];
	[self showWindow:nil];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
    [resHolder addObject:[NSNumber numberWithInteger:ret]];
}

- (IBAction)okClicked:(id)sender {
	[NSApp stopModalWithCode:0];
}

// Who invokes this and what does it do?
- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {    
    if([keyPath isEqualToString:@"operationCount"]) {
        if([object operationCount] == 0) {
            [indicator performSelectorOnMainThread:@selector(stopAnimation:) 
                                        withObject:self waitUntilDone:NO];
        }
    }
}

// Is this supposed to do anything?  It did nothing in 1.6.
- (void)doubleClickAction:(id)sender {

}


#pragma mark - Helper Methods

+ (NSString*)searchFileForSignatureFile:(NSString*)sigFile {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    NSString* file = [sigFile stringByDeletingPathExtension];
    BOOL isDir = NO;
    if([fmgr fileExistsAtPath:file isDirectory:&isDir] && !isDir)
        return file;
    else
        return nil;
}

+ (NSString*)searchSignatureFileForFile:(NSString*)sigFile {
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
