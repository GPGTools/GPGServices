//
//  RecipientWindowDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MacGPGME/MacGPGME.h>

@interface RecipientWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate> {
	IBOutlet NSTableView* tableView;
	
	GPGContext* gpgContext;
	
	NSArray* availableKeys;
	NSArray* keysMatchingSearch;
	
	NSIndexSet* indexSet;
	
	BOOL sign;
}

@property(readonly) NSArray* selectedKeys;
@property(assign) BOOL sign;

- (NSInteger)runModal;
- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;

@end
