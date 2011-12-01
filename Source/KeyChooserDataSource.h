//
//  KeyChooserDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 22.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Libmacgpg/Libmacgpg.h"

#import "GPGServices.h"

@interface KeyChooserDataSource : NSObject {
@private
    NSArray* availableKeys;
    GPGKey* selectedKey;
    NSUInteger selectedIndex;
    NSArray* keyDescriptions;
    
    KeyValidatorT keyValidator;
}

@property(retain) NSArray* availableKeys;
@property(retain) GPGKey* selectedKey;
@property(assign) NSUInteger selectedIndex;
@property(retain) NSArray* keyDescriptions;
@property(retain) KeyValidatorT keyValidator;

- (void)updateDescriptions;
- (NSArray*)getPrivateKeys;
- (GPGKey*)getDefaultKey;
- (void)update;

@end
