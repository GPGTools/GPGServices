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

@interface DummyVerificationController : NSWindowController <NSWindowDelegate> {
@private
    IBOutlet NSTableView* tableView;
    IBOutlet NSProgressIndicator* indicator;
    IBOutlet FileVerificationDataSource* dataSource;
    
	BOOL _terminateCanceled; // YES when the controller already called GPGServices -cancelTerminateTimer.
	id __strong _selfRetain; // Used to stay alive as long as the window is visiable.
}

@property (nonatomic, weak) IBOutlet NSScrollView *scrollView;
@property (nonatomic, weak) IBOutlet NSView *scrollIndicator;
@property (nonatomic, weak) IBOutlet NSButton *okButton;

- (IBAction)okClicked:(id)sender;


// thread-safe
+ (instancetype)verificationController;

// thread-safe
- (id)initWithWindowNibName:(NSString *)windowNibName;
// thread-safe
- (void)showWindow:(id)sender;
// thread-safe
- (void)addResults:(NSArray<NSDictionary *> *)results;


@end
