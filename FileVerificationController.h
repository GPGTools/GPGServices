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

    IBOutlet NSProgressIndicator* indicator;

    NSMutableSet* filesInVerification;
    NSMutableArray* verificationResults;
}

@property(retain) NSArray* filesToVerify;
@property(readonly) NSOperationQueue* verificationQueue;
@property(readonly) NSArray* verificationResults;

- (NSInteger)runModal;
- (IBAction)okClicked:(id)sender;

//Callback contains all successfully checked files
- (void)startVerification:(void(^)(NSArray*))callback;
- (void)addResults:(NSDictionary*)results;

#pragma mark - Helper Methods
- (NSString*)searchFileForSignatureFile:(NSString*)file;
- (NSString*)searchSignatureFileForFile:(NSString*)sigFile;

@end
