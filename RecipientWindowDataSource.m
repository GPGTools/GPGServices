//
//  RecipientWindowDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 05.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RecipientWindowDataSource.h"


@implementation RecipientWindowDataSource

- (void)awakeFromNib {
	gpgContext = [[GPGContext alloc] init];
	
	availableKeys = [[[gpgContext keyEnumeratorForSearchPattern:@"" secretKeysOnly:NO] allObjects] retain];
	keysMatchingSearch = [[NSArray alloc] initWithArray:availableKeys];
	
	//NSLog(@"availableKeys: %@", availableKeys);
	
	[tableView reloadData];
}

- (void)dealloc {
	[gpgContext release];
	[availableKeys release];
	[keysMatchingSearch release];
	
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
	else if([iden isEqualToString:@"expires"])
		return [key expirationDate];
	else if([iden isEqualToString:@"type"]) {
		if([key secretKey] == key)
			return @"sec";
		else if([key publicKey] == key)
			return @"pub";
	} 
	
	
	return @"";
	
	/*
	 SEL selector = NSSelectorFromString(iden);
	 if([key respondsToSelector:selector])
	 return [key performSelector:selector];
	 else
	 return @"";
	 */
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
	NSString* searchString = [[aNotification.object stringValue] lowercaseString];
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
	
	[tableView reloadData];
}

@end
