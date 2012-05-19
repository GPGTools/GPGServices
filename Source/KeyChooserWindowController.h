//
//  KeyChooserWindowController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
//#import "MacGPGME/MacGPGME.h"
#import "Libmacgpg/Libmacgpg.h"

#import "KeyChooserDataSource.h"

@interface KeyChooserWindowController : NSWindowController {
    IBOutlet NSPopUpButton* popupButton;
    BOOL _firstUpdated;
	KeyChooserDataSource *dataSource;
}

@property(retain) GPGKey* selectedKey;
@property (readonly) KeyChooserDataSource *dataSource;

// thread-safe
- (NSInteger)runModal; //Returns 0 on success

- (IBAction)chooseButtonClicked:(id)sender;
- (IBAction)cancelButtonClicked:(id)sender;

@end
