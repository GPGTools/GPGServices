//
//  RecipientWindowDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RecipientWindowController.h"
#import "GPGServices.h"

#import "GPGKey+utils.h"

@implementation RecipientWindowController

@synthesize okEnabled, selectedKeys, sign;

- (GPGKey*)selectedPrivateKey {
    return privateKeyDataSource.selectedKey;
}

- (void)setEncryptForOwnKeyToo:(BOOL)value {
	encryptForOwnKeyToo = value;
	self.okEnabled = encryptForOwnKeyToo || self.selectedKeys.count > 0;	
}

- (BOOL)encryptForOwnKeyToo {
	return encryptForOwnKeyToo;
}

- (id)init {
	self = [super initWithWindowNibName:@"RecipientWindow"];
    
	gpgController = [[GPGController gpgController] retain];
    encryptPredicate = [[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices canSignValidator]((GPGKey*)evaluatedObject);
    }] retain];
	
    availableKeys = [[[[gpgController allKeys] filteredSetUsingPredicate:[self validationPredicate]] 
                      sortedArrayUsingDescriptors:[keyTableView sortDescriptors]] retain];
	keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
    
    selectedKeys = [[NSMutableArray alloc] init];
	
    self.encryptForOwnKeyToo = YES;
    
	return self;
}

- (void)windowDidLoad {
	[super windowDidLoad];
	
    privateKeyDataSource.keyValidator = [GPGServices canSignValidator];
    
	[keyTableView setDoubleAction:@selector(doubleClickAction:)];
	[keyTableView setTarget:self];
    
    NSSortDescriptor* sd = [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                         ascending:YES
                                                          selector:@selector(localizedCaseInsensitiveCompare:)];
    [keyTableView setSortDescriptors:[NSArray arrayWithObject:sd]];
    [self tableView:keyTableView sortDescriptorsDidChange:nil];
    
    [self generateContextMenuForTable:keyTableView];
    
    NSUInteger idx = [keyTableView columnWithIdentifier:@"useKey"];
    if(idx != NSNotFound)
        [keyTableView moveColumn:idx toColumn:0];
}

- (void)dealloc {
    keyTableView.delegate = nil;
    keyTableView.dataSource = nil;
    searchField.delegate = nil;
    
	[gpgController release];
	[availableKeys release];
	[keysMatchingSearch release];
	
    [encryptPredicate release];
    
	[super dealloc];
}

#pragma mark -
#pragma mark Data Source

- (int)numberOfRowsInTableView:(NSTableView *)tableView {
	return [keysMatchingSearch count];
}

- (id)tableView:(NSTableView *)tableView 
objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(int)row {
	NSString* iden = tableColumn.identifier;
	GPGKey* key = [keysMatchingSearch objectAtIndex:row];
	
	if([iden isEqualToString:@"comment"])
		return [key comment];
	else if([iden isEqualToString:@"fingerprint"])
		return [key fingerprint];
	else if([iden isEqualToString:@"length"])
		return [NSNumber numberWithInt:[key length]];
	else if([iden isEqualToString:@"creationDate"])
		return [key creationDate];
	else if([iden isEqualToString:@"keyID"])
		return [key keyID];
	else if([iden isEqualToString:@"name"])
		return [key name];
	else if([iden isEqualToString:@"algorithm"])
		return [key algorithmDescription];
	else if([iden isEqualToString:@"shortKeyID"])
		return [key shortKeyID];
	else if([iden isEqualToString:@"email"])
		return [key email];
	else if([iden isEqualToString:@"expirationDate"])
		return [key expirationDate];
	else if([iden isEqualToString:@"type"]) {
		return [key type];
	} else if([iden isEqualToString:@"ownerTrust"]) {
        return [GPGKey validityDescription:[key ownerTrust]];
	} else if([iden isEqualToString:@"ownerTrustIndicator"]) {
        int i = 0;
        switch([key ownerTrust]) {
            case GPGValidityUnknown:
            case GPGValidityUndefined:
                i = 0; break;
            case GPGValidityNever:
                i = 1; break;
            case GPGValidityMarginal: 
                i = 2; break;
            case GPGValidityFull:
            case GPGValidityUltimate:
                i = 3; break;
        }
        
		return [NSNumber numberWithInt:i];
	} else if([iden isEqualToString:@"validity"]) {
        //return GPGValidityDescription([key overallValidity]);
        return [GPGKey validityDescription:[key overallValidity]];
	} else if([iden isEqualToString:@"validityIndicator"]) {
        int i = 0;
        switch([key overallValidity]) {
            case GPGValidityUnknown:
            case GPGValidityUndefined:
                i = 0; break;
            case GPGValidityNever:
                i = 1; break;
            case GPGValidityMarginal: 
                i = 2; break;
            case GPGValidityFull:
            case GPGValidityUltimate:
                i = 3; break;
        }
        
		return [NSNumber numberWithInt:i];
	} else if([iden isEqualToString:@"useKey"]) {
        GPGKey* k = [keysMatchingSearch objectAtIndex:row];
        return [NSNumber numberWithBool:[self.selectedKeys containsObject:k]];
    }

	return @"";
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row {
    if(tableView != keyTableView)
        return;
    
    if(row < keysMatchingSearch.count) {
        GPGKey* k = [keysMatchingSearch objectAtIndex:row];
        if([self.selectedKeys containsObject:k])
            [self.selectedKeys removeObject:k];
        else
            [self.selectedKeys addObject:k];
     
        self.okEnabled = self.encryptForOwnKeyToo || self.selectedKeys.count > 0;
        
        [tableView reloadData];
    }
}

- (void)displayItemsMatchingString:(NSString*)searchString {    
	if(searchString == nil ||
	   [searchString isEqualToString:@""]) {
		[keysMatchingSearch release];		
		keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
	} else {
        searchString = [searchString lowercaseString];
        
		NSMutableArray* newFilteredArray = [NSMutableArray array];
		[availableKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			GPGKey* k = (GPGKey*)obj;
            if([[k textForFilter] rangeOfString:searchString].location != NSNotFound)
                [newFilteredArray addObject:k];
		}];
		
        
		[keysMatchingSearch release];
		keysMatchingSearch = [newFilteredArray retain];
	}

    [keyTableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
	NSString* searchString = [[aNotification.object stringValue] lowercaseString];
    [self displayItemsMatchingString:searchString];
}

#pragma mark -
#pragma mark Delegate

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
    NSArray* tmp = [availableKeys sortedArrayUsingDescriptors:[keyTableView sortDescriptors]];
    [availableKeys release];
    availableKeys = [tmp retain];
    [self displayItemsMatchingString:[searchField stringValue]]; 
}

- (void)doubleClickAction:(id)sender {
	if([sender clickedRow] != -1 && 
	   [sender clickedRow] < keysMatchingSearch.count) {
        GPGKey* k = [keysMatchingSearch objectAtIndex:[sender clickedRow]];
     
        if([self.selectedKeys containsObject:k])
            [self.selectedKeys removeObject:k];
        else
            [self.selectedKeys addObject:k];
     
        self.okEnabled = self.encryptForOwnKeyToo || self.selectedKeys.count > 0;
        
        [keyTableView reloadData];
	}
}


//Next two methods borrowed from GPGKeychain
- (void)generateContextMenuForTable:(NSTableView *)table {
	NSMenuItem *menuItem;
	NSString *title;
	NSMenu *contextMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
	[[keyTableView headerView] setMenu:contextMenu];
	
	NSArray *columns = [keyTableView tableColumns];
	for (NSTableColumn *column in columns) {
        if([[column identifier] isEqualToString:@"useKey"] == NO) {
            title = [[column headerCell] title];
            if (![title isEqualToString:@""]) {
                menuItem = [contextMenu addItemWithTitle:title action:@selector(selectHeaderVisibility:) keyEquivalent:@""];
                [menuItem setTarget:self];
                [menuItem setRepresentedObject:column];
                [menuItem setState:[column isHidden] ? NSOffState : NSOnState];
            }
		}
	}
}

- (IBAction)selectHeaderVisibility:(NSMenuItem *)sender {
	[[sender representedObject] setHidden:sender.state];
	sender.state = !sender.state;
}

- (BOOL)tableView:(NSTableView *)tableView shouldReorderColumn:(NSInteger)columnIndex toColumn:(NSInteger)newColumnIndex {
    if(tableView != keyTableView)
        return YES;
    
    NSTableColumn* col = [[tableView tableColumns] objectAtIndex:columnIndex];
    
    if([[col identifier] isEqualToString:@"useKey"])
        return NO;
    else if(newColumnIndex == 0)
        return NO;
    else
        return YES;
}

#pragma mark Helpers

- (NSPredicate*)validationPredicate {
    return encryptPredicate;
}

#pragma mark -
#pragma mark Actions

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp stopModalWithCode:1];
}

- (NSInteger)runModal {
    [NSApp activateIgnoringOtherApps:YES];
	[self showWindow:self];
	NSInteger ret = [NSApp runModalForWindow:self.window];
	[self.window close];
	return ret;
}

- (IBAction)okClicked:(id)sender {
	[NSApp stopModalWithCode:0];
}

- (IBAction)cancelClicked:(id)sender {
	[NSApp stopModalWithCode:1];
}

@end
