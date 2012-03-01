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
    [selectedKey release];
    selectedKey = [selKey retain];
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
    self = [super init];
 
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
    [self update];
    
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
        c = (c && [c length]) ? [NSString stringWithFormat:@"(%@) ", c] : @"";
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
        return keys;
    }
}

- (GPGKey*)getDefaultKey {
    return [GPGServices myPrivateKey];
}

- (void)update {
    NSArray *nowAvailableKeys = [self getPrivateKeys];
    if (self.selectedKey && ![nowAvailableKeys containsObject:self.selectedKey])
        self.selectedKey = nil;
    self.availableKeys = nowAvailableKeys;

    GPGKey *nowDefaultKey = [self getDefaultKey];
    if (!nowDefaultKey)
        self.selectedKey = nil;
    else if ([nowAvailableKeys containsObject:nowDefaultKey])
        self.selectedKey = nowDefaultKey;

    [self updateDescriptions];
}


@end
