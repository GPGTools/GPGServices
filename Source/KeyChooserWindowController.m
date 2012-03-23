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

@synthesize dataSource = _dataSource;

@dynamic selectedKey;
- (void)setSelectedKey:(GPGKey *)selectedKey {
    self.dataSource.selectedKey = selectedKey;
}

- (GPGKey*)selectedKey {
    if (!_firstUpdated) {
        [self.dataSource update];
        _firstUpdated = TRUE;
    }
    return self.dataSource.selectedKey;
}

- (id)init {
    self = [super initWithWindowNibName:@"PrivateKeyChooserWindow"];
    _firstUpdated = FALSE;
    _dataSource = [[KeyChooserDataSource alloc] initWithValidator:[GPGServices isActiveValidator]];
    return self;
}

- (void)dealloc {
    [_dataSource release];
    [super dealloc];
}

- (void)windowDidLoad {
	[super windowDidLoad];
    [self selectedKey]; // call for _firstUpdate handling
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

/*
- (void)setKeyValidator:(KeyValidatorT)validator {
    dataSource.keyValidator = validator;  
    // [dataSource update];
    NSLog(@"setKeyValidator validator=%@ dataSource.keyValidator=%@ dataSource=%@",validator,dataSource.keyValidator,dataSource);
}
*/
 
@end
