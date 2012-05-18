//
//  RecipientWindowDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
//#import <MacGPGME/MacGPGME.h>
#import "Libmacgpg/Libmacgpg.h"

#import "KeyChooserDataSource.h"

@interface RecipientWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate> {
	IBOutlet NSTableView* keyTableView;
	IBOutlet NSSearchField* searchField;
		
	NSArray* availableKeys;
	NSArray* keysMatchingSearch;
    
    NSPredicate* encryptPredicate;
	
    NSMutableArray* selectedKeys;
	
	BOOL sign;
    BOOL encryptForOwnKeyToo;
    
    BOOL okEnabled;
    BOOL _firstUpdate;
	
	KeyChooserDataSource *dataSource;
}

@property (readonly) KeyChooserDataSource *dataSource;
@property (readonly) NSMutableArray* selectedKeys;
@property (readonly) GPGKey* selectedPrivateKey;
@property (assign) BOOL sign;
@property (assign) BOOL encryptForOwnKeyToo;
@property (assign) BOOL okEnabled;

// thread-safe
- (NSInteger)runModal;

- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;

@end
