#import <Cocoa/Cocoa.h>

@class SimpleTextWindow, SimpleTextView;

@protocol SimpleTextWindowDelegate <NSObject>
- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow;
@end

@interface SimpleTextWindow : NSWindowController <NSWindowDelegate> {
	NSString *text, *title;
    IBOutlet SimpleTextView * textView;
	id selfReference;
}
@property (strong) NSObject <SimpleTextWindowDelegate> *delegate;
@property (strong, readonly) NSString *text, *title;
+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate;
@end


