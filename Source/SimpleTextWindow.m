#import "SimpleTextWindow.h"
#import "SimpleTextView.h"

@interface SimpleTextWindow ()
@property (strong) NSString *text, *title;
@end

@implementation SimpleTextWindow
@synthesize text, title, delegate;


+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate {
	SimpleTextWindow *simpleTextWindow = [[SimpleTextWindow alloc] initWithWindowNibName:@"SimpleTextWindow"];
	simpleTextWindow.text = text;
	simpleTextWindow.title = title;
	simpleTextWindow.delegate = delegate;
	[simpleTextWindow.window makeKeyAndOrderFront:nil];
}

- (id)initWithWindow:(NSWindow *)window {
	if ((self = [super initWithWindow:window])) {
	}
	return self;
}

- (void)windowWillClose:(NSNotification *)notification {
	selfReference = nil;
	[[self delegate] simpleTextWindowWillClose:self];
}

- (void)setWindow:(NSWindow *)window {
	selfReference = self;
	window.level = NSFloatingWindowLevel;
	[super setWindow:window];
}

- (void) windowDidLoad {
    textView.textStorage.font = [NSFont userFixedPitchFontOfSize:12];
}

@end


