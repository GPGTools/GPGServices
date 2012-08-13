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

@interface RecipientWindowController ()

- (void)displayItemsMatchingString:(NSString*)s;
- (NSPredicate*)validationPredicate;
- (void)generateContextMenuForTable:(NSTableView *)table;
- (void)selectHeaderVisibility:(NSMenuItem *)sender;

- (void)runModalOnMain:(NSMutableArray *)resHolder;

@end

@implementation RecipientWindowController

@synthesize dataSource;
@synthesize selectedKeys, sign, symetricEncryption, encryptForOwnKeyToo;



+ (NSSet*)keyPathsForValuesAffectingOkEnabled {
	return [NSSet setWithObjects:@"encryptForOwnKeyToo", @"symetricEncryption", nil]; 
}

- (BOOL)okEnabled {
	return encryptForOwnKeyToo || symetricEncryption || self.selectedKeys.count > 0;
}

- (GPGKey*)selectedPrivateKey {
    if (!_firstUpdate) {
        [dataSource update];
        _firstUpdate = TRUE;
    }
    return dataSource.selectedKey;
}

/*- (void)setEncryptForOwnKeyToo:(BOOL)value {
	encryptForOwnKeyToo = value;
	//self.okEnabled = encryptForOwnKeyToo || self.selectedKeys.count > 0;	
}

- (BOOL)encryptForOwnKeyToo {
	return encryptForOwnKeyToo;
}*/

- (id)init {
	self = [super initWithWindowNibName:@"RecipientWindow"];

    dataSource = [[KeyChooserDataSource alloc] initWithValidator:[GPGServices canSignValidator]];

    encryptPredicate = [[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices canEncryptValidator]((GPGKey*)evaluatedObject);
    }] retain];

	GPGController* gpgController = [[GPGController gpgController] retain];
    availableKeys = [[[[gpgController allKeys] filteredSetUsingPredicate:[self validationPredicate]] 
                      sortedArrayUsingDescriptors:[keyTableView sortDescriptors]] retain];
	[gpgController release];
	keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];

    selectedKeys = [[NSMutableArray alloc] init];
	
    self.encryptForOwnKeyToo = YES;
    
	return self;
}

- (void)windowDidLoad {
	[super windowDidLoad];

    [self selectedPrivateKey]; // call for _firstUpdate handling
    
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
    [dataSource release];
    keyTableView.delegate = nil;
    keyTableView.dataSource = nil;
    searchField.delegate = nil;
    
	[availableKeys release];
	[keysMatchingSearch release];
	
    [encryptPredicate release];
    
	[super dealloc];
}

#pragma mark -
#pragma mark Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [keysMatchingSearch count];
}

- (id)tableView:(NSTableView *)tableView 
objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(NSInteger)row {
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
		
		[self willChangeValueForKey:@"okEnabled"];
		[self didChangeValueForKey:@"okEnabled"];
        //self.okEnabled = self.encryptForOwnKeyToo || self.selectedKeys.count > 0;
        
        [tableView reloadData];
    }
}

- (void)displayItemsMatchingString:(NSString*)searchString {    
	if(searchString.length == 0) {
		[keysMatchingSearch release];		
		keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
	} else {        
		NSMutableArray* newFilteredArray = [[NSMutableArray alloc] init];		
		[availableKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if([[(GPGKey *)obj textForFilter] rangeOfString:searchString options:NSCaseInsensitiveSearch].length > 0) {
                [newFilteredArray addObject:obj];
			}
		}];

		[keysMatchingSearch release];
		keysMatchingSearch = newFilteredArray;
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
     
		[self willChangeValueForKey:@"okEnabled"];
		[self didChangeValueForKey:@"okEnabled"];
        //self.okEnabled = self.encryptForOwnKeyToo || self.selectedKeys.count > 0;
        
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

- (void)selectHeaderVisibility:(NSMenuItem *)sender {
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

- (IBAction)okClicked:(id)sender {
	[NSApp stopModalWithCode:0];
}

- (IBAction)cancelClicked:(id)sender {
	[NSApp stopModalWithCode:1];
}

@end
