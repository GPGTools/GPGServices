//
//  KeyChooserWindowController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MacGPGME/MacGPGME.h"

@interface KeyChooserWindowController : NSWindowController {
    NSArray* availableKeys;
    GPGKey* chosenKey;
    
    IBOutlet NSPopUpButton* popupButton;
}

@property(retain) NSArray* availableKeys;
@property(retain) GPGKey* chosenKey;

- (NSInteger)runModal; //Returns 0 on success

- (NSArray*)getPrivateKeys;
- (GPGKey*)getDefaultKey;



@end
