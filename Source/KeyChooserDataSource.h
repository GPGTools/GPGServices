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
    NSInteger selectedIndex_;
    NSArray* keyDescriptions;
    
    KeyValidatorT keyValidator;
}

@property (strong) NSArray* availableKeys;
@property (strong) GPGKey* selectedKey;
@property (assign) NSInteger selectedIndex;
@property (strong) NSArray* keyDescriptions;
@property (copy) KeyValidatorT keyValidator;
@property (nonatomic, readonly) BOOL isEmpty;



- (id)initWithValidator:(KeyValidatorT)validator;
- (void)updateDescriptions;
- (NSArray*)getPrivateKeys;
- (GPGKey*)getDefaultKey;
- (void)update;

@end
