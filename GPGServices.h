//
//  GPGServices.h
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright 2006 far-blue.co.uk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MacGPGME/MacGPGME.h>

typedef enum {SignService, EncryptService, DecryptService, VerifyService, MyKeyService, MyFingerprintService, ImportKeyService} ServiceModeEnum;

@interface GPGServices : NSObject
{
	IBOutlet NSWindow *messageWindow;
	IBOutlet NSWindow *recipientWindow;
	IBOutlet NSTextField *messageHeadingText;
	IBOutlet NSTextField *messageBodyText;
	
	IBOutlet NSWindow *passphraseWindow;
	IBOutlet NSSecureTextField *passphraseText;
	
	NSTimer *currentTerminateTimer;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification;
-(void)importKey:(NSString *)inputString;
-(NSSet*)myKeys;
-(NSString *)myKey;
-(NSString *)signTextString:(NSString *)inputString;
-(NSString *)encryptTextString:(NSString *)inputString;
-(NSString *)decryptTextString:(NSString *)inputString;
-(void)verifyTextString:(NSString *)inputString;


-(void)dealWithPasteboard:(NSPasteboard *)pboard userData:(NSString *)userData mode:(ServiceModeEnum)mode error:(NSString **)error;
-(void)exitServiceRequest;
-(void)sign:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)encrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)decrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)verify:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myFingerprint:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)importKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;


-(void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body;
-(NSString *)context:(GPGContext *)context passphraseForKey:(GPGKey *)key again:(BOOL)again;

-(IBAction)closeModalWindow:(id)sender;

-(void)cancelTerminateTimer;
-(void)goneIn60Seconds;
-(void)selfQuit:(NSTimer *)timer;

@end
