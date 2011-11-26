//
//  KeyChooserWindowController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserWindowController.h"
#import "GPGServices.h"

@implementation KeyChooserWindowController

@dynamic selectedKey;
- (void)setSelectedKey:(GPGKey *)selectedKey {
    dataSource.selectedKey = selectedKey;
}

- (GPGKey*)selectedKey {
    return dataSource.selectedKey;
}

- (id)init {
    self = [super initWithWindowNibName:@"PrivateKeyChooserWindow"];
    return self;
}

- (void)dealloc {    
    [super dealloc];
}

- (IBAction)chooseButtonClicked:(id)sender {
    [NSApp stopModalWithCode:0];
}

- (IBAction)cancelButtonClicked:(id)sender {
    [NSApp stopModalWithCode:1];
}

- (void)windowWillClose:(NSNotification *)notification {
    if(notification.object == self.window && 
       [NSApp modalWindow] == self.window) {
        [NSApp stopModalWithCode:1];
    }
}

- (NSInteger)runModal {
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:self];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
	return ret;
}

- (void)setKeyValidator:(KeyValidatorT)validator {
    dataSource.keyValidator = validator;  
    // [dataSource update];
    NSLog(@"setKeyValidator validator=%@ dataSource.keyValidator=%@ dataSource=%@",validator,dataSource.keyValidator,dataSource);
}

@end
