//
//  KeyChooserWindowController.h
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MacGPGME/MacGPGME.h"

typedef BOOL(^KeyValidatorT)(GPGKey* key);

@interface KeyChooserWindowController : NSWindowController {
    NSArray* availableKeys;
    GPGKey* selectedKey;
    
    KeyValidatorT keyValidator;
    
    IBOutlet NSPopUpButton* popupButton;
}

@property(retain) NSArray* availableKeys;
@property(retain) GPGKey* selectedKey;
@property(retain) KeyValidatorT keyValidator;

- (void)prepareData;
- (NSInteger)runModal; //Returns 0 on success

- (NSArray*)getPrivateKeys;
- (GPGKey*)getDefaultKey;



@end
