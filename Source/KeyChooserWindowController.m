//
//  KeyChooserWindowController.m
//  GPGServices
//
//  Created by Moritz Ulrich on 16.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "KeyChooserWindowController.h"
#import "GPGServices.h"

@interface KeyChooserWindowController ()

- (void)runModalOnMain:(NSMutableArray *)resHolder;

@end

@implementation KeyChooserWindowController

@synthesize dataSource;

@dynamic selectedKey;
- (void)setSelectedKey:(GPGKey *)selectedKey {
    dataSource.selectedKey = selectedKey;
}

- (GPGKey*)selectedKey {
    if (!_firstUpdated) {
        [dataSource update];
        _firstUpdated = TRUE;
    }
    return dataSource.selectedKey;
}

- (id)init {
    self = [super initWithWindowNibName:@"PrivateKeyChooserWindow"];
    dataSource = [[KeyChooserDataSource alloc] initWithValidator:[GPGServices isActiveValidator]];
    return self;
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
    NSMutableArray *resHolder = [NSMutableArray arrayWithCapacity:1];
    [self performSelectorOnMainThread:@selector(runModalOnMain:) 
                           withObject:resHolder 
                        waitUntilDone:YES];
    return [[resHolder lastObject] integerValue];
}

// called by runModal
- (void)runModalOnMain:(NSMutableArray *)resHolder {
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:self];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
    [resHolder addObject:[NSNumber numberWithInteger:ret]];
}

/*
- (void)setKeyValidator:(KeyValidatorT)validator {
    dataSource.keyValidator = validator;  
    // [dataSource update];
    NSLog(@"setKeyValidator validator=%@ dataSource.keyValidator=%@ dataSource=%@",validator,dataSource.keyValidator,dataSource);
}
*/
 
@end
