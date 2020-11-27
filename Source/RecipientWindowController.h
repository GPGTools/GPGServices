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
#import <Zxcvbn/Zxcvbn.h>
#import "KeyChooserDataSource.h"



@interface RecipientWindowController : NSWindowController <NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate> {
	IBOutlet NSTableView *keyTableView;
	IBOutlet NSSearchField *searchField;
	
	NSString *selectedCountDescription;
	
	NSSet *availableKeys;
	NSArray *keysMatchingSearch;
    NSArray *_sortDescriptors;
	GPGValidityDescriptionTransformer *_validityTransformer;
	
    NSMutableSet *selectedKeys;
	
    BOOL _firstUpdate;
	
	KeyChooserDataSource *dataSource;
	
	DBZxcvbn *_zxcvbn;
}

@property (nonatomic, weak) id selectAll;
@property (nonatomic, readonly) NSString *selectedCountDescription;

@property (nonatomic, readonly) KeyChooserDataSource *dataSource;
@property (nonatomic, readonly) NSMutableSet *selectedKeys;
@property (nonatomic, readonly) GPGKey *selectedPrivateKey;
@property (nonatomic, assign) BOOL sign;
@property (nonatomic, assign) BOOL encryptForOwnKeyToo;
@property (nonatomic, assign) BOOL symetricEncryption;
@property (nonatomic, strong, readonly) NSString *password;
@property (nonatomic, readonly) BOOL okEnabled;
@property (nonatomic, readonly) NSAttributedString *versionAndBuildDescription;
@property (nonatomic, copy) NSArray *sortDescriptors;

// thread-safe
- (NSInteger)runModal;

- (IBAction)okClicked:(id)sender;
- (IBAction)cancelClicked:(id)sender;


@end
