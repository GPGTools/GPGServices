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

@synthesize availableKeys, selectedIndex, keyDescriptions, keyValidator;

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

    if(self.selectedIndex == NSNotFound)
        self.selectedIndex = 0;
    
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
}

- (void)updateDescriptions {
    NSMutableArray* arr = [NSMutableArray arrayWithCapacity:self.availableKeys.count];
    for(GPGKey* k in self.availableKeys) {
        NSString* c = [k comment];
        c = c ? [NSString stringWithFormat:@"(%@) ", c] : @"";
        [arr addObject:[NSString stringWithFormat:@"%@ - %@ %@<%@>",
                        [k shortKeyID], [k name], c, [k email]]];

    }
    
    self.keyDescriptions = arr;
}

- (NSArray*)getPrivateKeys {
    NSArray* keys = [[GPGServices myPrivateKeys] allObjects];

    if(self.keyValidator) 
        return [keys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            if([evaluatedObject isKindOfClass:[GPGKey class]])
                return self.keyValidator((GPGKey*)evaluatedObject);
            return NO;
        }]];
    else {
        NSLog(@"getPrivateKeys called with keyValidator=%@ using all private keys",self.keyValidator);        
        return keys;
    }
}

- (GPGKey*)getDefaultKey {
    GPGKey* key = [GPGServices myPrivateKey];
    
    if(key != nil)
        return key;
    else if(self.availableKeys.count > 0)
        return [self.availableKeys objectAtIndex:0];
    else
        return nil;
}

- (void)update {
    self.availableKeys = [self getPrivateKeys];
    self.selectedKey = [self getDefaultKey];
    
    if(self.selectedIndex == NSNotFound)
        self.selectedIndex = 0;
    
    [self updateDescriptions];
}


@end
