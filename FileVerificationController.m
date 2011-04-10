//
//  VerificationResultsController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 10.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "FileVerificationController.h"


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

- (void)startVerification:(void(^)(NSArray*))callback {
    for(NSString* file in self.filesToVerify) {
        [verificationQueue addOperationWithBlock:^(void) {

            BOOL verified = YES;
            
            NSColor* color = nil;
            if(verified)
                color = [NSColor greenColor];
            else
                color = [NSColor redColor];
            
            //Add to results
            NSDictionary* results = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [file lastPathComponent], @"filename",
                                     @"FULL TRUST - AWESOME", @"verificationResult", 
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

@end
