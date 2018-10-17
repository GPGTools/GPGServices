#import <Cocoa/Cocoa.h>

@class SimpleTextWindow, SimpleTextView;

@protocol SimpleTextWindowDelegate <NSObject>
- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow;
@end

@interface SimpleTextWindow : NSWindowController <NSWindowDelegate> {
    IBOutlet SimpleTextView *textView;
	id selfReference;
}
@property (nonatomic, strong) NSObject <SimpleTextWindowDelegate> *delegate;
@property (nonatomic, strong, readonly) NSAttributedString *text;
@property (nonatomic, strong, readonly) NSString *title;

+ (void)showText:(NSString *)text withTitle:(NSString *)title andDelegate:(NSObject <SimpleTextWindowDelegate> *)delegate;
@end


