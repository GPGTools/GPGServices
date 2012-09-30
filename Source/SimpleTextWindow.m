#import "SimpleTextWindow.h"

@interface SimpleTextWindow ()
@property (retain) NSString *text, *title;
@end

@implementation SimpleTextWindow
@synthesize text, title, delegate;


+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate {
	SimpleTextWindow *simpleTextWindow = [[[SimpleTextWindow alloc] initWithWindowNibName:@"SimpleTextWindow"] autorelease];
	simpleTextWindow.text = text;
	simpleTextWindow.title = title;
	simpleTextWindow.delegate = delegate;
	[simpleTextWindow.window makeKeyAndOrderFront:nil];
}

- (id)initWithWindow:(NSWindow *)window {
	if ((self = [super initWithWindow:window])) {
		[self retain];
	}
	return self;
}

- (void)windowWillClose:(NSNotification *)notification {
	[[self delegate] simpleTextWindowWillClose:self];
	[self release];
}

- (void)setWindow:(NSWindow *)window {
	window.level = NSFloatingWindowLevel;
	[super setWindow:window];
}


@end


