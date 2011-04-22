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
    
    [self bind:@"isActive" toObject:dataSource withKeyPath:@"isActive" options:nil];
    
    return self;
}

- (void)addResults:(NSDictionary*)results {
    [dataSource addResults:results];
}

- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file {
    [dataSource addResultFromSig:sig forFile:file];
}

- (IBAction)okClicked:(id)sender {
    [self close];
    [self release];
}

@end
