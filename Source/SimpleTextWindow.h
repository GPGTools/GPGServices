#import <Cocoa/Cocoa.h>

@class SimpleTextWindow, SimpleTextView;

@protocol SimpleTextWindowDelegate <NSObject>
- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow;
@end

@interface SimpleTextWindow : NSWindowController <NSWindowDelegate> {
	NSString *text, *title;
    IBOutlet SimpleTextView * textView;
}
@property (unsafe_unretained) NSObject <SimpleTextWindowDelegate> *delegate;
@property (strong, readonly) NSString *text, *title;
+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate;
@end


