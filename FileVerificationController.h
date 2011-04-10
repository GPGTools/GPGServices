//
//  VerificationResultsController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 10.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface FileVerificationController : NSWindowController {
@private
    NSArray* filesToVerify;
    NSOperationQueue* verificationQueue;

    BOOL queueIsActive;
    
    NSMutableArray* verificationResults;
}

@property(retain) NSArray* filesToVerify;
@property(readonly) BOOL queueIsActive;
@property(readonly) NSOperationQueue* verificationQueue;
@property(readonly) NSArray* verificationResults;

//Callback contains all successfully checked files
- (void)startVerification:(void(^)(NSArray*))callback;
- (void)addResults:(NSDictionary*)results;

@end
