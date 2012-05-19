//
//  VerificationResultsController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 10.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class FileVerificationDataSource;

@interface FileVerificationController : NSWindowController {
@private
    NSArray* filesToVerify;
    NSOperationQueue* verificationQueue;

    IBOutlet NSTableView* tableView;
    IBOutlet NSProgressIndicator* indicator;
    IBOutlet FileVerificationDataSource* dataSource;
    
    NSMutableSet* filesInVerification;
}

@property(retain) NSArray* filesToVerify;
@property(readonly) NSOperationQueue* verificationQueue;

// threadSafe
- (NSInteger)runModal;

- (IBAction)okClicked:(id)sender;

#pragma mark - Helper Methods
+ (NSString*)searchFileForSignatureFile:(NSString*)file;
+ (NSString*)searchSignatureFileForFile:(NSString*)sigFile;

@end
