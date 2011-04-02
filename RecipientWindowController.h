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
	IBOutlet NSTableView* keyTableView;
	IBOutlet NSSearchField* searchField;
    IBOutlet KeyChooserDataSource* privateKeyDataSource;
	
	GPGContext* gpgContext;
	
	NSArray* availableKeys;
	NSArray* keysMatchingSearch;
    
    NSPredicate* encryptPredicate;
    NSPredicate* encryptSignPredicate;
	
    NSMutableArray* selectedKeys;
	
	BOOL sign;
    BOOL encryptForOwnKeyToo;
    
    BOOL okEnabled;
}

@property(readonly) NSMutableArray* selectedKeys;
@property(readonly) GPGKey* selectedPrivateKey;
@property(assign) BOOL sign;
@property(assign) BOOL encryptForOwnKeyToo;
@property(assign) BOOL okEnabled;

- (NSPredicate*)validationPredicate;
- (void)displayItemsMatchingString:(NSString*)s;
- (NSInteger)runModal;
- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;

- (void)generateContextMenuForTable:(NSTableView *)table;
- (IBAction)selectHeaderVisibility:(NSMenuItem *)sender;

@end
