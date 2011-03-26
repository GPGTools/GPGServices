//
//  RecipientWindowDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RecipientWindowController.h"
#import "GPGServices.h"

@implementation RecipientWindowController

@synthesize encryptForOwnKeyToo;

- (NSArray*)selectedKeys {
	if(indexSet == nil || 
	   indexSet.count == 0)
		return nil;
	else
		return [keysMatchingSearch objectsAtIndexes:indexSet];
}

- (GPGKey*)selectedPrivateKey {
    return privateKeyDataSource.selectedKey;
}

- (void)setSign:(BOOL)s {
    sign = s;
    
    [availableKeys release];
    availableKeys = [[[[gpgContext keyEnumeratorForSearchPatterns:[NSArray array]
                                                   secretKeysOnly:NO] 
                       allObjects] 
                      filteredArrayUsingPredicate:[self validationPredicate]] retain];
    
    [self displayItemsMatchingString:[searchField stringValue]];
}

- (BOOL)sign {
    return sign;
}

- (id)init {
	self = [super initWithWindowNibName:@"RecipientWindow"];
    
	gpgContext = [[GPGContext alloc] init];
    encryptPredicate = [[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices canSignValidator]((GPGKey*)evaluatedObject);
    }] retain];
    encryptSignPredicate = [[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        GPGKey* k = (GPGKey*)evaluatedObject;
        
        return ([GPGServices canSignValidator](k) && 
                [GPGServices canEncryptValidator](k));
        
    }] retain];
	
	availableKeys = [[[[gpgContext keyEnumeratorForSearchPatterns:[NSArray array]
                                                   secretKeysOnly:NO] 
                      allObjects] 
                      filteredArrayUsingPredicate:[self validationPredicate]] retain];
	keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
	
    self.sign = NO;
    self.encryptForOwnKeyToo = YES;
    
	return self;
}

- (void)windowDidLoad {
	[super windowDidLoad];
	
    privateKeyDataSource.keyValidator = [GPGServices canSignValidator];
    
	[tableView setDoubleAction:@selector(doubleClickAction:)];
	[tableView setTarget:self];
    NSSortDescriptor* sd = [NSSortDescriptor sortDescriptorWithKey:@"name"
                                                         ascending:YES
                                                          selector:@selector(localizedCaseInsensitiveCompare:)];
    [tableView setSortDescriptors:[NSArray arrayWithObject:sd]];
	[tableView reloadData];
}

- (void)dealloc {
    tableView.delegate = nil;
    tableView.dataSource = nil;
    searchField.delegate = nil;
    
	[gpgContext release];
	[availableKeys release];
	[keysMatchingSearch release];
	
    [encryptPredicate release];
    [encryptSignPredicate release];
    
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
		if([key secretKey] == key)
			return @"sec";
		else if([key publicKey] == key)
			return @"pub";
	} else if([iden isEqualToString:@"ownerTrust"]) {
        return [key ownerTrustDescription];
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
	}

    

	return @"";
}

- (void)displayItemsMatchingString:(NSString*)searchString {
    NSArray* oldSelectedKeys = self.selectedKeys;
    
	if(searchString == nil ||
	   [searchString isEqualToString:@""]) {
		[keysMatchingSearch release];		
		keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
	} else {
		//Search name, shortKeyID, keyID, email comment and fingerprint for the string (case-insensitive)
		//Somethat ugly... 
		NSMutableArray* newFilteredArray = [NSMutableArray array];
		[availableKeys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			GPGKey* k = (GPGKey*)obj;
			if([[[k name] lowercaseString]rangeOfString:searchString].location != NSNotFound ||
			   [[[k shortKeyID] lowercaseString] rangeOfString:searchString].location != NSNotFound ||
			   [[[k keyID] lowercaseString] rangeOfString:searchString].location != NSNotFound ||
			   [[[k email] lowercaseString] rangeOfString:searchString].location != NSNotFound ||
			   [[[k comment] lowercaseString] rangeOfString:searchString].location != NSNotFound ||
			   [[[k fingerprint] lowercaseString] rangeOfString:searchString].location != NSNotFound)
				[newFilteredArray addObject:k];
		}];
		
		[keysMatchingSearch release];
		keysMatchingSearch = [newFilteredArray retain];
	}
    
    NSSet* oldKeySet = [NSSet setWithArray:oldSelectedKeys];
    NSIndexSet* idxsOfSelectedKeys = [keysMatchingSearch indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        return [oldKeySet containsObject:obj];
    }];

    [tableView reloadData];
    [tableView selectRowIndexes:idxsOfSelectedKeys byExtendingSelection:NO];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
	NSString* searchString = [[aNotification.object stringValue] lowercaseString];
    [self displayItemsMatchingString:searchString];
}

#pragma mark -
#pragma mark Delegate

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors {
    NSArray* tmp = [availableKeys sortedArrayUsingDescriptors:[tableView sortDescriptors]];
    [availableKeys release];
    availableKeys = [tmp retain];
    [self displayItemsMatchingString:[searchField stringValue]]; 
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	NSIndexSet* set = [tableView selectedRowIndexes];
	
	[self willChangeValueForKey:@"selectedKeys"];
	[indexSet release];
	indexSet = (set.count == 0) ? nil : [set retain];
	[self didChangeValueForKey:@"selectedKeys"];
}

- (void)doubleClickAction:(id)sender {
	if([sender clickedRow] != -1 && 
	   [sender clickedRow] < keysMatchingSearch.count) {
		[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:[sender clickedRow]]
			   byExtendingSelection:NO];
		[self okClicked:sender];
	}
}

#pragma mark Helpers

- (NSPredicate*)validationPredicate {
    if(sign)
        return encryptSignPredicate;
    else
        return encryptPredicate;
}

#pragma mark -
#pragma mark Actions

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp stopModalWithCode:1];
}

- (NSInteger)runModal {
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

- (void)keyDown:(NSEvent *)theEvent {	
	if([theEvent modifierFlags] & NSCommandKeyMask &&
	   [[theEvent characters] isEqualToString:@"f"])
		[self.window makeFirstResponder:searchField];
	else
		[super keyDown:theEvent];
}

@end
