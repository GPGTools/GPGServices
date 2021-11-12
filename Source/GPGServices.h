//
//  GPGServices.h
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright 2006 far-blue.co.uk. All rights reserved.
//  Modified by Mento © 2020.
//

#import <Cocoa/Cocoa.h>
#import "Libmacgpg/Libmacgpg.h"
#import <UserNotifications/UserNotifications.h>

typedef BOOL(^KeyValidatorT)(GPGKey* key);


extern NSString *const ALL_VERIFICATION_RESULTS_KEY;
extern NSString *const OPERATION_IDENTIFIER_KEY;
extern NSString *const VERIFICATION_CONTROLLER_KEY;
extern NSString *const VERIFICATION_FAILED_KEY;
extern NSString *const NOTIFICATION_TITLE_KEY;
extern NSString *const NOTIFICATION_MESSAGE_KEY;
extern NSString *const ALERT_TITLE_KEY;
extern NSString *const ALERT_MESSAGE_KEY;
extern NSString *const RESULT_FILENAME_KEY;
extern NSString *const RESULT_FILE_KEY;
extern NSString *const RESULT_ICON_NAME_KEY;
extern NSString *const RESULT_ICON_COLOR_KEY;
extern NSString *const RESULT_FINGERPRINT_KEY;
extern NSString *const RESULT_SIGNEE_KEY;
extern NSString *const RESULT_SIGNEE_NAME_KEY;
extern NSString *const RESULT_SIGNEE_EMAIL_KEY;
extern NSString *const RESULT_DETAILS_KEY;




@interface GPGServices : NSObject



- (void)cancelTerminateTimer;
- (void)goneIn60Seconds;


#pragma mark -
#pragma mark GPG-Helper

+ (NSSet*)myPrivateKeys;
+ (GPGKey*)myPrivateKey;
+ (NSString *)myPrivateFingerprint;

#pragma mark -
#pragma mark Validators

+ (KeyValidatorT)canSignValidator;
+ (KeyValidatorT)canEncryptValidator;
+ (KeyValidatorT)isActiveValidator;


#pragma mark -
#pragma mark Service handling routines

-(void)sign:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)encrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)decrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)verify:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myFingerprint:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)importKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;


#pragma mark -
#pragma mark UI Helpher

- (void)displayNotificationWithTitle:(NSString *)title message:(NSString *)message files:(NSArray *)files userInfo:(NSDictionary *)userInfo failed:(BOOL)failed;


@end

@interface NSImage (BigSurSFSymbols)
+ (instancetype)imageWithSystemSymbolName:(NSString *)symbolName accessibilityDescription:(NSString *)description;
@end


