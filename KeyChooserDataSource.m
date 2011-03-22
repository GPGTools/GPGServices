//
//  KeyChooserDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserDataSource.h"

@implementation KeyChooserDataSource

@synthesize availableKeys, selectedIndex, keyDescriptions, keyValidator;
@dynamic selectedKey;

//Todo support key-value-binding for this
- (GPGKey*)selectedKey {
    if(self.selectedIndex < self.availableKeys.count)
        return [self.availableKeys objectAtIndex:self.selectedIndex];
    else
        return nil;
}

- (void)setSelectedKey:(GPGKey *)selKey {
    [selectedKey release];
    selectedKey = [selKey retain];
    self.selectedIndex = [self.availableKeys indexOfObject:selKey];
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
    [self updateDescriptions];
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
    NSArray* keys = [[context keyEnumeratorForSearchPattern:@"" secretKeysOnly:YES] allObjects];
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

@end
