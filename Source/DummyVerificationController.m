//
//  FileVerificationDummyController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "DummyVerificationController.h"
#import "FileVerificationDataSource.h"

@implementation DummyVerificationController

@synthesize isActive;

- (id)initWithWindowNibName:(NSString *)windowNibName {
    self = [super initWithWindowNibName:windowNibName];
        
    return self;
}

- (void)windowDidLoad {
    [self bind:@"isActive" toObject:dataSource withKeyPath:@"isActive" options:nil];
}

- (void)addResults:(NSDictionary*)results {
    [dataSource addResults:results];
}

- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file {
    [dataSource addResultFromSig:sig forFile:file];
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

@end
