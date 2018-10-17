#import "SimpleTextWindow.h"
#import "SimpleTextView.h"

@interface SimpleTextWindow ()
@property (nonatomic, strong) NSAttributedString *text;
@property (nonatomic, strong) NSString *title;
@end

@implementation SimpleTextWindow


+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate {
	SimpleTextWindow *simpleTextWindow = [[SimpleTextWindow alloc] initWithWindowNibName:@"SimpleTextWindow"];
	
	NSDictionary *attributes = @{NSForegroundColorAttributeName: [NSColor labelColor], NSFontAttributeName: [NSFont userFixedPitchFontOfSize:12]};

	simpleTextWindow.text = [[NSAttributedString alloc] initWithString:text attributes:attributes];
	simpleTextWindow.title = title;
	simpleTextWindow.delegate = delegate;
	[simpleTextWindow.window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
	selfReference = nil;
	[self.delegate simpleTextWindowWillClose:self];
}

- (void)setWindow:(NSWindow *)window {
	selfReference = self;
	window.level = NSFloatingWindowLevel;
	super.window = window;
}

@end


