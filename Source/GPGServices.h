//
//  GPGServices.h
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright 2006 far-blue.co.uk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MacGPGME/MacGPGME.h>
#import <Growl/Growl.h>

typedef BOOL(^KeyValidatorT)(GPGKey* key);

typedef enum {
    SignService, 
    EncryptService, 
    DecryptService, 
    VerifyService, 
    MyKeyService, 
    MyFingerprintService, 
    ImportKeyService,
} ServiceModeEnum;

typedef enum {
    SignFileService, 
    EncryptFileService, 
    DecryptFileService, 
    VerifyFileService,
    ImportFileService,
} FileServiceModeEnum;


#pragma mark Growl Constants

#define gpgGrowlOperationSucceededName (@"Operation Succeeded")
#define gpgGrowlOperationFailedName (@"Operation Failed")

@interface GPGServices : NSObject <GrowlApplicationBridgeDelegate>
{
	IBOutlet NSWindow *recipientWindow;
	
	IBOutlet NSWindow *passphraseWindow;
	IBOutlet NSSecureTextField *passphraseText;
	
	NSTimer *currentTerminateTimer;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification;


#pragma mark -
#pragma mark GPG-Helper

- (void)importKeyFromData:(NSData*)inputData;
- (void)importKey:(NSString *)inputString;
+ (NSSet*)myPrivateKeys;
+ (GPGKey*)myPrivateKey;

#pragma mark -
#pragma mark Validators

+ (KeyValidatorT)canSignValidator;
+ (KeyValidatorT)canEncryptValidator;
+ (KeyValidatorT)isActiveValidator;

#pragma mark -
#pragma mark Text Stuff

-(NSString *)myFingerprint;
-(NSString *)myKey;
-(NSString *)signTextString:(NSString *)inputString;
-(NSString *)encryptTextString:(NSString *)inputString;
-(NSString *)decryptTextString:(NSString *)inputString;
-(void)verifyTextString:(NSString *)inputString;


#pragma mark -
#pragma mark File Stuff

- (NSString*)normalizedAndUniquifiedPathFromPath:(NSString*)path;
- (NSNumber*)folderSize:(NSString *)folderPath;
- (NSNumber*)sizeOfFiles:(NSArray*)files;

- (NSString*)detachedSignFile:(NSString*)file withKeys:(NSArray*)keys;
- (void)signFiles:(NSArray*)files;
- (GPGData*)signedGPGDataForGPGData:(GPGData*)dataToSign withKeys:(NSArray*)keys;
- (void)encryptFiles:(NSArray*)files;
- (void)decryptFiles:(NSArray*)files; 
- (void)verifyFiles:(NSArray*)files;
- (void)importFiles:(NSArray*)files;

#pragma mark NSPredicates for filtering file arrays

- (NSPredicate*)fileExistsPredicate;
- (NSPredicate*)isDirectoryPredicate;
//- (NSPredicate*)isZipPredicate;

#pragma mark -
#pragma mark Service handling routines

-(void)dealWithPasteboard:(NSPasteboard *)pboard
                 userData:(NSString *)userData 
                     mode:(ServiceModeEnum)mode
                    error:(NSString **)error;
-(void)dealWithFilesPasteboard:(NSPasteboard *)pboard
                      userData:(NSString *)userData
                          mode:(FileServiceModeEnum)mode
                         error:(NSString **)error;

-(void)exitServiceRequest;
-(void)sign:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)encrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)decrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)verify:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)myFingerprint:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)importKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;

-(void)signFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)encryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)decryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)validateFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;
-(void)importFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error;

#pragma mark -
#pragma mark UI Helpher

-(void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body;
- (void)displaySignatureVerificationForSig:(GPGSignature*)sig;
-(NSString *)context:(GPGContext *)context passphraseForKey:(GPGKey *)key again:(BOOL)again;
-(IBAction)closeModalWindow:(id)sender;
- (NSURL*)getFilenameForSavingWithSuggestedPath:(NSString*)path
                         withSuggestedExtension:(NSString*)ext;

-(void)cancelTerminateTimer;
-(void)goneIn60Seconds;
-(void)selfQuit:(NSTimer *)timer;

@end
