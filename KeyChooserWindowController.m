//
//  KeyChooserWindowController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserWindowController.h"


@implementation KeyChooserWindowController

@synthesize availableKeys, selectedKey, keyValidator;

- (id)init {
    self = [super initWithWindowNibName:@"PrivateKeyChooserWindow"];
    
    return self;
}

- (void)dealloc {
    self.availableKeys = nil;
    self.selectedKey = nil;
    self.keyValidator = nil;
    
    [super dealloc];
}

- (void)prepareData {    
    self.availableKeys = [self getPrivateKeys];
    self.selectedKey = [self getDefaultKey];
    
    [popupButton removeAllItems];
    for(GPGKey* key in self.availableKeys) {
        NSMutableString* description = [NSMutableString string];
        [description appendFormat:@"%@ - %@ (%@) <%@>",
         [key shortKeyID], [key name], [key comment], [key email]];
        [popupButton addItemWithTitle:description];
    } 
    
    NSUInteger idx = [self.availableKeys indexOfObject:self.selectedKey];
    [popupButton selectItemAtIndex:idx];

}

- (IBAction)chooseButtonClicked:(id)sender {
    NSUInteger idx = popupButton.indexOfSelectedItem;
    if(idx >= self.availableKeys.count)
        self.selectedKey = nil;
    else
        self.selectedKey = [self.availableKeys objectAtIndex:idx];
    
    [NSApp stopModalWithCode:0];
}

- (IBAction)cancelButtonClicked:(id)sender {
    self.selectedKey = nil;
    
    [NSApp stopModalWithCode:1];
}

- (void)windowWillClose:(NSNotification *)notification {
    if(notification.object == self.window && 
       [NSApp modalWindow] == self.window) {
        [NSApp stopModalWithCode:1];
    }
}

- (NSInteger)runModal {
    [self prepareData];
    
    [self.window center];
    [self.window display];
    return [NSApp runModalForWindow:self.window];
}

#pragma mark -
#pragma mark GPG Helpers

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
