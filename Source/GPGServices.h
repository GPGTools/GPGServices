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
