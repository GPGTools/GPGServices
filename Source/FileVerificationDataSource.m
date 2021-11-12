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
#import "GPGVerificationResultCellView.h"
#import "GPGServices.h"


@interface FileVerificationDataSource () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@property (nonatomic, weak) IBOutlet NSScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *verificationResults;
@property (nonatomic) BOOL calculatedRowHeight;
@property (nonatomic) NSMutableIndexSet *calulatedRows;
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
	[self.tableView reloadData];
}



- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return _verificationResults.count;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	GPGVerificationResultCellView *cellView = [tableView makeViewWithIdentifier:@"VerificationResult" owner:self];
	NSDictionary *verificationResult = _verificationResults[row];
	
	cellView.titleField.stringValue = verificationResult[ALERT_TITLE_KEY] ? verificationResult[ALERT_TITLE_KEY] : @"";
	cellView.nameField.stringValue = verificationResult[RESULT_SIGNEE_NAME_KEY] ? verificationResult[RESULT_SIGNEE_NAME_KEY] : @"";
	cellView.emailField.stringValue = verificationResult[RESULT_SIGNEE_EMAIL_KEY] ? verificationResult[RESULT_SIGNEE_EMAIL_KEY] : @"";
	cellView.fingerprintField.stringValue = verificationResult[RESULT_FINGERPRINT_KEY] ? verificationResult[RESULT_FINGERPRINT_KEY] : @"";
	cellView.filenameField.stringValue = verificationResult[RESULT_FILENAME_KEY] ? verificationResult[RESULT_FILENAME_KEY] : @"";
	
	
	id encodedDetailsMessage = verificationResult[RESULT_DETAILS_KEY];
	if (!encodedDetailsMessage) {
		cellView.textField.stringValue = @"";
	} else if ([encodedDetailsMessage isKindOfClass:[NSString class]]) {
		cellView.textField.stringValue = encodedDetailsMessage;
	} else {
		NSMutableAttributedString *detailsMessage = [(NSAttributedString *)[NSKeyedUnarchiver unarchivedObjectOfClass:[NSAttributedString class] fromData:encodedDetailsMessage error:nil] mutableCopy];
		// Add the font attributes form the textfield, so the string is displayed correctly.
		NSTextField *textField = cellView.textField;
		NSDictionary *attributes = @{NSFontAttributeName: textField.font};
		[detailsMessage addAttributes:attributes  range:NSMakeRange(0, detailsMessage.length)];
		textField.attributedStringValue = detailsMessage;
	}
	
	
	NSString *iconName = verificationResult[RESULT_ICON_NAME_KEY] ? verificationResult[RESULT_ICON_NAME_KEY] : @"xmark.seal.fill";
	NSString *iconColorKey = verificationResult[RESULT_ICON_COLOR_KEY];
	NSColor *iconColor;

	if ([iconColorKey isEqualToString:@"green"]) {
		iconColor = [NSColor colorWithCalibratedRed:0.373 green:0.848 blue:0.19 alpha:1];
	} else if ([iconColorKey isEqualToString:@"yellow"]) {
		iconColor = [NSColor colorWithCalibratedRed:0.847 green:0.77 blue:0.129 alpha:1];
	} else {
		iconColor = [NSColor colorWithCalibratedRed:0.808 green:0.241 blue:0.241 alpha:1];
	}
	
	// Color the icon.
	NSImage *image;
	if ([NSImage respondsToSelector:@selector(imageWithSystemSymbolName:accessibilityDescription:)]) {
		image = [NSImage imageWithSystemSymbolName:iconName accessibilityDescription:nil];
	} else {
		image = [NSImage imageNamed:iconName];
	}
	
	NSImage *tintedImage = image.copy;
	tintedImage.template = YES;

	[tintedImage lockFocus];
	[iconColor set];
	
	NSRect rect = {NSZeroPoint, tintedImage.size};
	NSRectFillUsingOperation(rect, NSCompositingOperationSourceIn);
	
	[tintedImage unlockFocus];
	tintedImage.template = NO;
	cellView.imageView.image = tintedImage;
	
	if (!self.calculatedRowHeight) {
		self.calculatedRowHeight = YES;
		self.calulatedRows = [NSMutableIndexSet new];
		
		
		[cellView layoutSubtreeIfNeeded];
		
		NSLayoutConstraint *constraint = [NSLayoutConstraint
										  constraintWithItem:self.scrollView
										  attribute:NSLayoutAttributeHeight
										  relatedBy:NSLayoutRelationGreaterThanOrEqual
										  toItem:nil
										  attribute:NSLayoutAttributeNotAnAttribute
										  multiplier:1.0
										  constant:cellView.fittingSize.height + 8];
		constraint.priority = NSLayoutPriorityDefaultHigh;
		constraint.active = YES;
	}
	
	if (![self.calulatedRows containsIndex:row]) {
		[self.calulatedRows addIndex:row];
		
		NSRect frame = cellView.frame;
		frame.size.width = 10;
		cellView.frame = frame;
		
		[cellView layoutSubtreeIfNeeded];
		
		NSLayoutConstraint *constraint = [NSLayoutConstraint
										 constraintWithItem:self.scrollView
										 attribute:NSLayoutAttributeWidth
										 relatedBy:NSLayoutRelationGreaterThanOrEqual
										 toItem:nil
										 attribute:NSLayoutAttributeNotAnAttribute
										 multiplier:1.0
										 constant:cellView.frame.size.width + 20];
		constraint.priority = NSLayoutPriorityDefaultHigh;
		constraint.active = YES;
		
	}

	return cellView;
}

@end
