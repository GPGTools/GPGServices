//
//  RecipientWindowDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MacGPGME/MacGPGME.h>

#import "KeyChooserDataSource.h"

@interface RecipientWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate> {
	IBOutlet NSTableView* tableView;
	IBOutlet NSSearchField* searchField;
    IBOutlet KeyChooserDataSource* privateKeyDataSource;
	
	GPGContext* gpgContext;
	
	NSArray* availableKeys;
	NSArray* keysMatchingSearch;
    
    NSPredicate* encryptPredicate;
    NSPredicate* encryptSignPredicate;
	
	NSIndexSet* indexSet;
	
	BOOL sign;
}

@property(readonly) NSArray* selectedKeys;
@property(assign) BOOL sign;

- (NSPredicate*)validationPredicate;
- (void)displayItemsMatchingString:(NSString*)s;
- (NSInteger)runModal;
- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;
- (IBAction)signClicked:(NSButton*)sender;

@end
