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
    if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
        // The command key is the ONLY modifier key being pressed.
        if ([[event charactersIgnoringModifiers] isEqualToString:@"x"]) {
            return [NSApp sendAction:@selector(cut:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"c"]) {
            return [NSApp sendAction:@selector(copy:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"v"]) {
            return [NSApp sendAction:@selector(paste:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"a"]) {
            return [NSApp sendAction:@selector(selectAll:) to:[[self window] firstResponder] from:self];
        }
    }
    return [super performKeyEquivalent:event];
}

@end

@implementation ShortcutHandlingSearchField

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
        // The command key is the ONLY modifier key being pressed.
        if ([[event charactersIgnoringModifiers] isEqualToString:@"x"]) {
            return [NSApp sendAction:@selector(cut:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"c"]) {
            return [NSApp sendAction:@selector(copy:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"v"]) {
            return [NSApp sendAction:@selector(paste:) to:[[self window] firstResponder] from:self];
        } else if ([[event charactersIgnoringModifiers] isEqualToString:@"a"]) {
            return [NSApp sendAction:@selector(selectAll:) to:[[self window] firstResponder] from:self];
        }
    }
    return [super performKeyEquivalent:event];
}

@end
