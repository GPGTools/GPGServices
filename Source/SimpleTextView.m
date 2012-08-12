/*
 Copyright © Moritz Ulrich, 2011
 Copyright © Roman Zechmeister, 2012
 
 Dieses Programm ist freie Software. Sie können es unter den Bedingungen 
 der GNU General Public License, wie von der Free Software Foundation 
 veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß 
 Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren Version.
 
 Die Veröffentlichung dieses Programms erfolgt in der Hoffnung, daß es Ihnen 
 von Nutzen sein wird, aber ohne irgendeine Garantie, sogar ohne die implizite 
 Garantie der Marktreife oder der Verwendbarkeit für einen bestimmten Zweck. 
 Details finden Sie in der GNU General Public License.
 
 Sie sollten ein Exemplar der GNU General Public License zusammen mit diesem 
 Programm erhalten haben. Falls nicht, siehe <http://www.gnu.org/licenses/>.
*/

#import "SimpleTextView.h"

@implementation SimpleTextView

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask) {
        // The command key is the ONLY modifier key being pressed.
        if ([[event charactersIgnoringModifiers] isEqualToString:@"c"]) {
			[self copy:self];
			return YES;
        }
		else if ([[event charactersIgnoringModifiers] isEqualToString:@"a"]) {
			[self selectAll:self];
			return YES;
        }
		else if ([[event charactersIgnoringModifiers] isEqualToString:@"w"] || [[event charactersIgnoringModifiers] isEqualToString:@"q"]) {
			[[self window] close];
			return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)copy:(id)sender {
	if ([[[self selectedRanges] objectAtIndex:0] rangeValue].length == 0) {
		[[NSPasteboard generalPasteboard] declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
		[[NSPasteboard generalPasteboard] setString:self.string forType:NSStringPboardType];
	}
	else {
		[super copy:nil];
	}
}

@end

