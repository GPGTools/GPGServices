//
//  GPGVerificationResultCellView.h
//  GPGServices
//
//  Created by Mento on 07.05.21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface GPGVerificationResultCellView : NSTableCellView

@property (nullable, weak) IBOutlet NSTextField *titleField;
@property (nullable, weak) IBOutlet NSTextField *nameField;
@property (nullable, weak) IBOutlet NSTextField *emailField;
@property (nullable, weak) IBOutlet NSTextField *fingerprintField;
@property (nullable, weak) IBOutlet NSTextField *filenameField;


@end

NS_ASSUME_NONNULL_END
