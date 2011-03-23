//
//  KeyChooserDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserDataSource.h"

@implementation KeyChooserDataSource

@synthesize availableKeys, selectedIndex, keyDescriptions;

- (GPGKey*)selectedKey {
    if(self.selectedIndex < self.availableKeys.count)
        return [self.availableKeys objectAtIndex:self.selectedIndex];
    else
        return nil;
}

- (void)setSelectedKey:(GPGKey *)selKey {
    [self willChangeValueForKey:@"selectedKey"];
    [selectedKey release];
    selectedKey = [selKey retain];
    [self didChangeValueForKey:@"selectedKey"];
    
    self.selectedIndex = [self.availableKeys indexOfObject:selKey];
}

- (void)setKeyValidator:(KeyValidatorT)kv {
    [self willChangeValueForKey:@"keyValidator"];
    [keyValidator release];
    keyValidator = [kv retain];
    [self didChangeValueForKey:@"keyValidator"];
}

- (KeyValidatorT)keyValidator {
    return keyValidator;
}

- (id)init {
    self = [super init];
 
    [self addObserver:self 
           forKeyPath:@"availableKeys"
              options:NSKeyValueObservingOptionNew
              context:nil];
    [self addObserver:self 
           forKeyPath:@"keyValidator"
              options:NSKeyValueObservingOptionNew
              context:nil];
    
    self.availableKeys = [self getPrivateKeys];
    self.selectedKey = [self getDefaultKey];
    
    [self updateDescriptions];
    
    return self;
}

- (void)dealloc {
    [self removeObserver:self forKeyPath:@"availableKeys"];
    [self removeObserver:self forKeyPath:@"keyValidator"];
    
    self.availableKeys = nil;
    self.selectedKey = nil;
    self.keyValidator = nil;
    
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {    

    if([keyPath isEqualToString:@"keyValidator"])
        self.availableKeys = [self getPrivateKeys];
    
    [self updateDescriptions];
    
    NSLog(@"availableKeys: %@", self.availableKeys);
}

- (void)updateDescriptions {
    NSMutableArray* arr = [NSMutableArray arrayWithCapacity:self.availableKeys.count];
    for(GPGKey* k in self.availableKeys) {
        [arr addObject:[NSString stringWithFormat:@"%@ - %@ (%@) <%@>",
                        [k shortKeyID], [k name], [k comment], [k email]]];

    }
    
    self.keyDescriptions = [NSArray arrayWithArray:arr];
}

- (NSArray*)getPrivateKeys {
    GPGContext* context = [[GPGContext alloc] init];
    
    NSMutableArray* keys = [NSMutableArray array];
    for(GPGKey* k in [[context keyEnumeratorForSearchPattern:@"" secretKeysOnly:YES] allObjects]) {
        // BUG in gpg <= 1.2.x: secret keys have no capabilities when listed in batch!
        // That's why we refresh key.
        // Also from GPGMail
        [keys addObject:[context refreshKey:k]];
    }
    
    [context release];
    
    if(self.keyValidator) 
        return [keys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if([evaluatedObject isKindOfClass:[GPGKey class]])
                return self.keyValidator((GPGKey*)evaluatedObject);
            return NO;
        }]];
    else
        return keys;
}

- (GPGKey*)getDefaultKey {
    GPGOptions *myOptions=[[GPGOptions alloc] init];
	NSString *keyID=[myOptions optionValueForName:@"default-key"];
	[myOptions release];
	if(keyID == nil)
        return nil;
    
	GPGContext *aContext = [[GPGContext alloc] init];
    
	NS_DURING
    GPGKey* defaultKey=[aContext keyFromFingerprint:keyID secretKey:YES];
    [aContext release];
    return defaultKey;
    NS_HANDLER
    [aContext release];
    return nil;
	NS_ENDHANDLER
    
    return nil;
}


#pragma mark -
#pragma mark Validators

- (KeyValidatorT)canSignValidator {
	// A subkey can be expired, without the key being, thus making key useless because it has
	// no other subkey...
	// We don't care about ownerTrust, validity
    // Copied from GPGMail's GPGMailBundle.m
    KeyValidatorT block =  ^(GPGKey* key) {
        for (GPGSubkey *aSubkey in [key subkeys]) {
            if ([aSubkey canSign] && 
                ![aSubkey hasKeyExpired] && 
                ![aSubkey isKeyRevoked] && 
                ![aSubkey isKeyInvalid] && 
                ![aSubkey isKeyDisabled])
                return YES;
        }
        return NO;
    };
    
    return [[block copy] autorelease];
}

@end
