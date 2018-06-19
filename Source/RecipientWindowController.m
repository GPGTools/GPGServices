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
@property (nonatomic, strong) NSArray *keysMatchingSearch;

- (void)displayItemsMatchingString:(NSString*)s;
- (void)generateContextMenuForTable:(NSTableView *)table;
- (void)selectHeaderVisibility:(NSMenuItem *)sender;

- (void)runModalOnMain:(NSMutableArray *)resHolder;

- (void) persistSelectedKeys;
- (void) restoreSelectedKeys;

@property (readonly) BOOL selectAllMixed;

@end

@implementation RecipientWindowController
@synthesize dataSource, selectedKeys, sign, symetricEncryption, encryptForOwnKeyToo, keysMatchingSearch, sortDescriptors=_sortDescriptors;



+ (NSSet*)keyPathsForValuesAffectingSelectedCountDescription {
	return [NSSet setWithObjects:@"selectedKeys", @"availableKeys", nil];
}
- (NSString *)selectedCountDescription {
	return [NSString stringWithFormat:[GPGServices localizedStringForKey:@"SelectedKeysDescription"], selectedKeys.count, availableKeys.count];
}


+ (NSSet*)keyPathsForValuesAffectingSelectAll {
	return [NSSet setWithObjects:@"selectedKeys", nil];
}
- (id)selectAll {
	NSUInteger selectedCount = selectedKeys.count;
	if (selectedCount == 0) {
		return @(0);
	} else if (availableKeys.count > selectedCount) {
		return NSMultipleValuesMarker;
	}
	return @(1);
}
- (void)setSelectAll:(id)value {
	[self willChangeValueForKey:@"selectedKeys"];
	if ([value intValue] == 0) {
		[selectedKeys removeAllObjects];
	} else if ([value intValue] == 1) {
		[selectedKeys setSet:availableKeys];
	}
	[keyTableView reloadData];
	[self didChangeValueForKey:@"selectedKeys"];
}



+ (NSSet*)keyPathsForValuesAffectingOkEnabled {
	return [NSSet setWithObjects:@"encryptForOwnKeyToo", @"symetricEncryption", @"selectedKeys", nil];
}
- (BOOL)okEnabled {
	return encryptForOwnKeyToo || symetricEncryption || self.selectedKeys.count > 0;
}


- (GPGKey *)selectedPrivateKey {
    if (!_firstUpdate) {
        [dataSource update];
        _firstUpdate = TRUE;
    }
    return dataSource.selectedKey;
}


- (NSAttributedString *)versionAndBuildDescription {
	NSMutableAttributedString *description = [NSMutableAttributedString new];
	NSMutableString *mutableString = description.mutableString;
	[mutableString appendFormat:NSLocalizedString(@"Version: %@", nil), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
	[mutableString appendString:@"  "];
	NSUInteger grayStart = description.length;
	[mutableString appendFormat:NSLocalizedString(@"Build: %@", nil), [[NSBundle mainBundle] objectForInfoDictionaryKey:@"BuildNumber"]];
	[description addAttribute:NSForegroundColorAttributeName value:[NSColor grayColor] range:NSMakeRange(grayStart, description.length - grayStart)];

	return description;
}




#pragma mark -
#pragma mark init, dealloc etc.

- (id)init {
	self = [super initWithWindowNibName:@"RecipientWindow"];

    dataSource = [[KeyChooserDataSource alloc] initWithValidator:[GPGServices canSignValidator]];

	
	availableKeys = [[[GPGKeyManager sharedInstance] allKeys] objectsPassingTest:^BOOL(GPGKey *key, BOOL *stop) {
		return key.canAnyEncrypt && key.validity < GPGValidityInvalid;
	}];
	
	
	
	self.keysMatchingSearch = [availableKeys allObjects];

    selectedKeys = [[NSMutableSet alloc] init];
    [self restoreSelectedKeys];
	
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
    [self tableView:keyTableView sortDescriptorsDidChange:@[]];
    
    [self generateContextMenuForTable:keyTableView];
    
    NSUInteger idx = [keyTableView columnWithIdentifier:@"useKey"];
    if(idx != NSNotFound)
        [keyTableView moveColumn:idx toColumn:0];
}

#pragma mark -
#pragma mark Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return [keysMatchingSearch count];
}

- (id)tableView:(NSTableView *)tableView 
objectValueForTableColumn:(NSTableColumn *)tableColumn
			row:(NSInteger)row {
	NSString *iden = tableColumn.identifier;
	GPGKey *key = [keysMatchingSearch objectAtIndex:row];
	
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
		return key.keyID.shortKeyID;
	else if([iden isEqualToString:@"email"])
		return [key email];
	else if([iden isEqualToString:@"expirationDate"])
		return [key expirationDate];
	else if([iden isEqualToString:@"type"]) {
		return key.secret ? @"sec" : @"pub";
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
			default:
				break;
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
			default:
				break;
        }
        
		return [NSNumber numberWithInt:i];
	} else if([iden isEqualToString:@"useKey"]) {
        GPGKey *k = [keysMatchingSearch objectAtIndex:row];
		NSNumber *result = [NSNumber numberWithBool:[self.selectedKeys containsObject:k]];
		return result;
	}

	return @"";
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row {
	
	if (tableView != keyTableView || row >= keysMatchingSearch.count || ![column.identifier isEqualToString:@"useKey"]) {
        return;
	}
	
	GPGKey *k = [keysMatchingSearch objectAtIndex:row];
	
	[self willChangeValueForKey:@"selectedKeys"];
	if ([(NSNumber *)value boolValue]) {
		[self.selectedKeys addObject:k];
	} else {
		[self.selectedKeys removeObject:k];
	}
	
	[self didChangeValueForKey:@"selectedKeys"];

}

- (void)displayItemsMatchingString:(NSString*)searchString {
	NSSet *filteredKeys = availableKeys;
	if(searchString.length > 0) {
		filteredKeys = [filteredKeys objectsPassingTest:^BOOL(GPGKey *key, BOOL *stop) {
            return [key.textForFilter rangeOfString:searchString options:NSCaseInsensitiveSearch].length > 0;
		}];
	}
	
	// Place selected keys on the top of the list.
	NSSortDescriptor *selectedSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES comparator:^NSComparisonResult(id obj1, id obj2) {
		return [self.selectedKeys containsObject:obj2] - [self.selectedKeys containsObject:obj1];
	}];
	NSMutableArray *sortDescriptors = [NSMutableArray arrayWithObject:selectedSortDescriptor];
	[sortDescriptors addObjectsFromArray:self.sortDescriptors];
	
	// Sort the keys.
	self.keysMatchingSearch = [[filteredKeys allObjects] sortedArrayUsingDescriptors:sortDescriptors];
	
    [keyTableView reloadData];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
	NSString* searchString = [[aNotification.object stringValue] lowercaseString];
    [self displayItemsMatchingString:searchString];
}

- (void)setSortDescriptors:(NSArray *)sortDescriptors {
	if (sortDescriptors != _sortDescriptors) {
		_sortDescriptors = [sortDescriptors copy];
		
		[self displayItemsMatchingString:[searchField stringValue]];
	}
}

#pragma mark -
#pragma mark Delegate

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(__unused NSArray *)oldDescriptors {
	self.sortDescriptors = [keyTableView sortDescriptors];
}

- (void)doubleClickAction:(NSTableView *)sender {
	NSInteger clickedRow = sender.clickedRow;
	if (clickedRow > -1 && clickedRow < keysMatchingSearch.count && sender.clickedColumn != 0) {
        GPGKey *k = [keysMatchingSearch objectAtIndex:clickedRow];
		
		[self willChangeValueForKey:@"selectedKeys"];
		if ([self.selectedKeys containsObject:k]) {
            [self.selectedKeys removeObject:k];
		} else {
            [self.selectedKeys addObject:k];
		}
		[self didChangeValueForKey:@"selectedKeys"];
		
        [keyTableView reloadData];
	}
}


//Next two methods borrowed from GPGKeychain
- (void)generateContextMenuForTable:(NSTableView *)table {
	NSMenuItem *menuItem;
	NSString *title;
	NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:@""];
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
    
    [self persistSelectedKeys];
}

- (IBAction)cancelClicked:(id)sender {
	[NSApp stopModalWithCode:1];
}

- (NSString *)selectedKeysDefaultsKey {
    return [NSStringFromClass( [self class] ) stringByAppendingString:@"SelectedKeys"];
}

- (void)persistSelectedKeys {
    NSMutableArray * keyIds = [[NSMutableArray alloc] init];
    for ( GPGKey * key in selectedKeys ) {
        [keyIds addObject:key.keyID];
    }
    [[NSUserDefaults standardUserDefaults] setValue:keyIds
                                             forKey:[self selectedKeysDefaultsKey]];
}

- (void)restoreSelectedKeys {
    NSArray * keyIds = [[NSUserDefaults standardUserDefaults] valueForKey:[self selectedKeysDefaultsKey]];
    for ( NSString * keyId in keyIds ) {
        for ( GPGKey * key in availableKeys ) {
            if ( [key.keyID isEqualToString:keyId] ) {
                [selectedKeys addObject:key];
            }
        }
    }
}

@end
