//
//  FileVerificationDummyController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class FileVerificationDataSource;
@class GPGSignature;

@interface DummyVerificationController : NSWindowController {
@private
    IBOutlet NSTableView* tableView;
    IBOutlet NSProgressIndicator* indicator;
    IBOutlet FileVerificationDataSource* dataSource;
    
    BOOL isActive;
}

@property(assign) BOOL isActive;

// thread-safe
- (void)showWindow:(id)sender;
// thread-safe
- (void)addResults:(NSDictionary*)results;
// thread-safe
- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file;
// thread-safe
- (NSInteger)runModal;

- (IBAction)okClicked:(id)sender;

@end
