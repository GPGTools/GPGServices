//
//  ShortcutHandlingFields.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ShortcutHandlingFields.h"

@implementation ShortcutHandlingTextField

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (([event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand) {
        // The command key is the ONLY modifier key being pressed.
		SEL selector = nil;
		NSString *characters = event.charactersIgnoringModifiers;
        if ([characters isEqualToString:@"x"]) {
			selector = @selector(cut:);
        } else if ([characters isEqualToString:@"c"]) {
			selector = @selector(copy:);
        } else if ([characters isEqualToString:@"v"]) {
			selector = @selector(paste:);
        } else if ([characters isEqualToString:@"a"]) {
			selector = @selector(selectAll:);
        }
		if (selector) {
            return [NSApp sendAction:selector to:self.window.firstResponder from:self];
		}
    }
    return [super performKeyEquivalent:event];
}

@end

@implementation ShortcutHandlingSearchField

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (([event modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand) {
        // The command key is the ONLY modifier key being pressed.
		SEL selector = nil;
		NSString *characters = event.charactersIgnoringModifiers;
        if ([characters isEqualToString:@"x"]) {
			selector = @selector(cut:);
        } else if ([characters isEqualToString:@"c"]) {
			selector = @selector(copy:);
        } else if ([characters isEqualToString:@"v"]) {
			selector = @selector(paste:);
        } else if ([characters isEqualToString:@"a"]) {
			selector = @selector(selectAll:);
        }
		if (selector) {
            return [NSApp sendAction:selector to:self.window.firstResponder from:self];
		}
    }
    return [super performKeyEquivalent:event];
}

@end
