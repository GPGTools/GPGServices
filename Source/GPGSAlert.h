//
//  GPGSAlert.h
//  GPGServices
//
//  Created by Mento on 06.04.20.
//

#import <Cocoa/Cocoa.h>

@interface GPGSAlert : NSWindowController

@property (nonatomic, strong) NSString *messageText;
@property (nonatomic, strong) NSString *informativeText;
@property (nonatomic, copy) NSArray *files;


- (void)show;

@end

