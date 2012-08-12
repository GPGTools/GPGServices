#import <Cocoa/Cocoa.h>

@class SimpleTextWindow;

@protocol SimpleTextWindowDelegate <NSObject>
- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow;
@end

@interface SimpleTextWindow : NSWindowController <NSWindowDelegate> {
	NSObject <SimpleTextWindowDelegate> *delegate;
	NSString *text, *title;
}
@property (assign) NSObject <SimpleTextWindowDelegate> *delegate;
@property (retain, readonly) NSString *text, *title;
+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate;
@end


