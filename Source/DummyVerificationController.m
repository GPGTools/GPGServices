//
//  FileVerificationDummyController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DummyVerificationController.h"
#import "FileVerificationDataSource.h"

@interface DummyVerificationController (ThreadSafety)

- (void)setIsActiveOnMain:(NSNumber *)isActive;
- (void)showWindowOnMain:(id)sender;
- (void)addResultsOnMain:(NSDictionary *)results;
- (void)addResultFromSigOnMain:(NSArray *)args;
- (void)runModalOnMain:(NSMutableArray *)resHolder;

@end

@implementation DummyVerificationController

@synthesize isActive = _isActive;

- (id)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
        
    return self;
}

- (void)setIsActive:(BOOL)isActive {
    [self performSelectorOnMainThread:@selector(setIsActiveOnMain:) 
                           withObject:[NSNumber numberWithBool:isActive] waitUntilDone:NO];
}

// called by setIsActive
- (void)setIsActiveOnMain:(NSNumber *)isActive {
    [self willChangeValueForKey:@"isActive"];
    _isActive = [isActive boolValue];
    [self didChangeValueForKey:@"isActive"];
}

- (void)windowDidLoad {
    [self bind:@"isActive" toObject:dataSource withKeyPath:@"isActive" options:nil];
}

- (void)showWindow:(id)sender {
    [self performSelectorOnMainThread:@selector(showWindowOnMain:) withObject:sender waitUntilDone:NO];
}

// called by showWindow:
- (void)showWindowOnMain:(id)sender {
    [super showWindow:sender];
}

- (void)addResults:(NSDictionary*)results {
    [self performSelectorOnMainThread:@selector(addResultsOnMain:) withObject:results waitUntilDone:NO];
}

// called by addResults:
- (void)addResultsOnMain:(NSDictionary *)results {
    [dataSource addResults:results];
}
     
- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file {
    [self performSelectorOnMainThread:@selector(addResultFromSigOnMain:) 
                           withObject:[NSArray arrayWithObjects:sig, file, nil] 
                        waitUntilDone:NO];
}

// called by addResultFromSig:forFile:
- (void)addResultFromSigOnMain:(NSArray *)args {
    GPGSignature *sig = [args objectAtIndex:0];
    NSString *file = [args objectAtIndex:1];
    [dataSource addResultFromSig:sig forFile:file];
}

- (NSInteger)runModal {
    NSMutableArray *resHolder = [NSMutableArray arrayWithCapacity:1];
    [self performSelectorOnMainThread:@selector(runModalOnMain:) withObject:resHolder waitUntilDone:YES];
    return [[resHolder lastObject] integerValue];
}

// called by runModal
- (void)runModalOnMain:(NSMutableArray *)resHolder {
    [NSApp activateIgnoringOtherApps:YES];
	[self showWindow:self];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
	[resHolder addObject:[NSNumber numberWithInteger:ret]];
}

- (IBAction)okClicked:(id)sender {
	[NSApp stopModalWithCode:0];
}

- (void)windowWillClose:(NSNotification *)notification {
	[NSApp stopModalWithCode:0];
}


@end
