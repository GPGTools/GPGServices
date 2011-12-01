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
    IBOutlet KeyChooserDataSource* dataSource;
    IBOutlet NSPopUpButton* popupButton;
}

@property(retain) GPGKey* selectedKey;

- (NSInteger)runModal; //Returns 0 on success
// - (void)setKeyValidator:(KeyValidatorT)validator;

- (IBAction)chooseButtonClicked:(id)sender;
- (IBAction)cancelButtonClicked:(id)sender;

@end
