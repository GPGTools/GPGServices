//
//  NSArray+join.m
//  GPGServices
//
//  Created by Mento on 28.08.20.
//

#import "NSArray+join.h"

@implementation NSArray (AttributedJoin)

- (NSAttributedString *)attributedLinesJoined {
	// Concatenate the (attributed) strings using a new-line.
	
	NSMutableAttributedString *attributedVerficationResult = [NSMutableAttributedString new];
	NSUInteger count = self.count;
	NSAttributedString *newLine = [[NSAttributedString alloc] initWithString:@"\n"];
	for (NSUInteger i = 0; i < count; i++) {
		id line = self[i];
		NSAttributedString *attributedLine = line;
		if ([line isKindOfClass:[NSString class]]) {
			attributedLine = [[NSAttributedString alloc] initWithString:line];
		}
		[attributedVerficationResult appendAttributedString:attributedLine];
		
		if (i + 1 < count) {
			[attributedVerficationResult appendAttributedString:newLine];
		}
	}
	
	return attributedVerficationResult;
}

@end
