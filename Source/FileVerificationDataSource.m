//
//  FileVerificationDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
//#import <MacGPGME/MacGPGME.h>
#import "Libmacgpg/Libmacgpg.h"

#import "FileVerificationDataSource.h"

@interface FileVerificationDataSource () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@property (nonatomic, strong) NSMutableArray *verificationResults;
@end

@implementation FileVerificationDataSource

- (id)init {
    self = [super init];
    
    _verificationResults = [NSMutableArray new];
    
    return self;
}

- (void)setTableView:(NSTableView *)tableView {
	_tableView = tableView;
	_tableView.intercellSpacing = NSMakeSize(3, 8);
	_tableView.usesAutomaticRowHeights = YES;
}


- (void)addResults:(NSArray<NSDictionary *> *)results {
	NSAssert([NSThread isMainThread], @"-addResultsFromSigs:forFile: called on background thread.");
	
	[_verificationResults addObjectsFromArray:results];
}



- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return _verificationResults.count;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSString *identifier = tableColumn.identifier;
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
	
	if ([identifier isEqualToString:@"filename"]) {
		cellView.textField.stringValue = _verificationResults[row][@"filename"];
	} else if ([identifier isEqualToString:@"result"]) {
		cellView.textField.attributedStringValue = _verificationResults[row][@"verificationResult"];
	} else {
		NSAssert(NO, @"Unkown column identifier!");
		return nil;
	}
	
	return cellView;
}

@end
