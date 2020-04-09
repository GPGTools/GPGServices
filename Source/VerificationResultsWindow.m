//
//  VerificationResultsWindow.m
//  GPGServices
//
//  Created by Mento on 23.03.20.
//

#import "VerificationResultsWindow.h"

@implementation VerificationResultsWindow

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
	self = [super initWithContentRect:contentRect styleMask:style backing:backingStoreType defer:flag];
	if (!self) {
		return nil;
	}
	
	[self standardWindowButton:NSWindowCloseButton].hidden = YES;
	[self standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
	[self standardWindowButton:NSWindowZoomButton].hidden = YES;
	
	return self;
}

@end
