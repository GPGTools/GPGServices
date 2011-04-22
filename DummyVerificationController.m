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
