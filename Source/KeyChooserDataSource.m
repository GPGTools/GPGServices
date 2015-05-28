//
//  KeyChooserDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserDataSource.h"
#import "GPGServices.h"

@implementation KeyChooserDataSource

@synthesize availableKeys, keyDescriptions, keyValidator;

- (GPGKey*)selectedKey {
    return selectedKey;
}

- (void)setSelectedKey:(GPGKey *)selKey {
    if ([selKey isEqual:selectedKey])
        return;

    [self willChangeValueForKey:@"selectedKey"];
    NSUInteger keyindex = [self.availableKeys indexOfObject:selKey];
    selectedKey = selKey;
    [self didChangeValueForKey:@"selectedKey"];
    
    self.selectedIndex = keyindex;
}

- (NSInteger)selectedIndex {
    return selectedIndex_;
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (selectedIndex == selectedIndex_)
        return;

    [self willChangeValueForKey:@"selectedIndex"];
    GPGKey *keyobject = (selectedIndex >= 0 && selectedIndex < [self.availableKeys count])
    ? [self.availableKeys objectAtIndex:selectedIndex] : nil;
    selectedIndex_ = selectedIndex;
    [self didChangeValueForKey:@"selectedIndex"];

    self.selectedKey = keyobject;
}

- (id)init {
    return [self initWithValidator:nil];
}

- (id)initWithValidator:(KeyValidatorT)validator {
    if (self = [super init]) { 
        keyValidator = validator;

        [self addObserver:self 
               forKeyPath:@"availableKeys"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
        [self addObserver:self 
               forKeyPath:@"keyValidator"
                  options:NSKeyValueObservingOptionNew
                  context:nil];
        
        selectedIndex_ = -1;
        self->selectedKey = nil;
    }
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"availableKeys"];
    [self removeObserver:self forKeyPath:@"keyValidator"];

    self.selectedKey = nil;
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {    
    
    if([keyPath isEqualToString:@"keyValidator"]) {
        [self update];
    }
    else {
        [self updateDescriptions];
    }
}

- (void)updateDescriptions {
    NSMutableArray* arr = [NSMutableArray arrayWithCapacity:self.availableKeys.count];
    for(GPGKey* k in self.availableKeys) {
        NSString* c = [k comment];
        c = (c && [c length]) ? [NSString stringWithFormat:@"(%@) ", c] : @"";
        [arr addObject:[NSString stringWithFormat:@"%@ - %@ %@<%@>",
                        k.keyID.shortKeyID, k.name, c, k.email]];
    }
    
    self.keyDescriptions = arr;
}

- (NSArray*)getPrivateKeys {
    NSSet* keys = [GPGServices myPrivateKeys];

    if (self.keyValidator) {
		keys =[keys objectsPassingTest:^BOOL(GPGKey *key, BOOL *stop) {
			return self.keyValidator(key);
		}];
	}
	return [keys allObjects];
}

- (GPGKey*)getDefaultKey {
    return [GPGServices myPrivateKey];
}

- (void)update {
    NSArray *nowAvailableKeys = [self getPrivateKeys];
    if (self.selectedKey && ![nowAvailableKeys containsObject:self.selectedKey])
        self.selectedKey = nil;
    self.availableKeys = nowAvailableKeys;

    GPGKey *nowSelected = self.selectedKey;
    if (!nowSelected) {
        NSString *privFingerprint = [GPGServices myPrivateFingerprint];
        if (privFingerprint) {
            for (GPGKey *key in self.availableKeys) {
				if ([key.allFingerprints member:privFingerprint]) {
                    nowSelected = key;
                    break;
                }
            }
        }
        else if ([self.availableKeys count] == 1) {
            nowSelected = [self.availableKeys objectAtIndex:0];
        }
    }
    self.selectedIndex = [self.availableKeys indexOfObject:nowSelected];

    [self updateDescriptions];
}


@end
