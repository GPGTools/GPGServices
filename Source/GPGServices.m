//
//  GPGServices.m
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "GPGServices.h"

#import "RecipientWindowController.h"
#import "KeyChooserWindowController.h"
#import "FileVerificationController.h"
#import "DummyVerificationController.h"
#import "InProgressWindowController.h"
#import "ServiceWorker.h"
#import "ServiceWorkerDelegate.h"
#import "ServiceWrappedArgs.h"
#import "GPGTempFile.h"

#import "Libmacgpg/GPGFileStream.h"
#import "Libmacgpg/GPGMemoryStream.h"
#import "ZipOperation.h"
#import "ZipKit/ZKArchive.h"
#import "NSPredicate+negate.h"
#import "GPGKey+utils.h"
#import "NSAlert+ThreadSafety.h"

#define SIZE_WARNING_LEVEL_IN_MB 10
static const float kBytesInMB = 1.e6; // Apple now uses this vs 2^20
static NSString * const tempTemplate = @"_gpg(XXX).tmp";
static NSUInteger const suffixLen = 5;

@interface GPGServices ()
- (void)removeWorker:(id)worker;
- (void)displayOperationFinishedNotificationWithTitleOnMain:(NSArray *)args;
- (void)displayOperationFailedNotificationWithTitleOnMain:(NSArray *)args;
- (void)displaySignatureVerificationForSigOnMain:(GPGSignature*)sig;

// Pass in an array of files. 
// singleFmt should include %@ for the file name (e.g., "Decrypting %@");
// pluralFmt should include %u for [files count] (e.g., "Decrypting %u files");
- (NSString *)describeOperationForFiles:(NSArray *)files 
                          singleFileFmt:(NSString *)singleFmt
                         pluralFilesFmt:(NSString *)pluralFmt;

// Pass in an array of files and successCount
// singleFmt should include %@ for the file name (e.g., "Decrypted %@");
// singleFailFmt should include %@ for the file name (e.g., "Failed to decrypt %@")
// pluralFmt should include %1$u for successCount and %2$u for [files count] 
//   (e.g., "Decrypted %1$u of %2$u files");
- (NSString *)describeCompletionForFiles:(NSArray *)files 
                            successCount:(NSUInteger)successCount
                           singleFileFmt:(NSString *)singleFmt 
                           singleFailFmt:(NSString *)singleFailFmt
                          pluralFilesFmt:(NSString *)pluralFmt;
- (void)signFilesSync:(ServiceWrappedArgs *)wrappedArgs;
- (void)decryptFilesSync:(ServiceWrappedArgs *)wrappedArgs;
- (void)encryptFilesSync:(ServiceWrappedArgs *)wrappedArgs;
- (void)verifyFilesSync:(ServiceWrappedArgs *)wrappedArgs;
- (void)importFilesSync:(ServiceWrappedArgs *)wrappedArgs;

// to allow easily putting under a new NSAutoreleasePool

- (void)signFilesWrapped:(ServiceWrappedArgs *)wrappedArgs;
- (void)encryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs;
- (void)decryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs; 
- (void)verifyFilesWrapped:(ServiceWrappedArgs *)wrappedArgs;
- (void)importFilesWrapped:(ServiceWrappedArgs *)wrappedArgs;
- (NSString*)detachedSignFileWrapped:(ServiceWrappedArgs *)wrappedArgs file:(NSString*)file withKeys:(NSArray*)keys;

// If growl is active, produce one for a file's signatures
- (void)growlVerificationResultsFor:(NSString *)file signatures:(NSArray *)signatures;

@end

@implementation GPGServices

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[NSApp setServicesProvider:self];
    //	NSUpdateDynamicServices();
	currentTerminateTimer=nil;
    
    [GrowlApplicationBridge setGrowlDelegate:self];
    _inProgressCtlr = [[InProgressWindowController alloc] init];
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    if([[filename pathExtension] isEqualToString:@"gpg"]) {
        [self decryptFiles:[NSArray arrayWithObject:filename]];
    }
    
	return NO;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
    NSArray* encs = [filenames pathsMatchingExtensions:[NSArray arrayWithObject:@"gpg"]];
    NSArray* sigs = [filenames pathsMatchingExtensions:[NSArray arrayWithObjects:@"sig", @"asc", nil]];
    
    if(encs != nil && encs.count != 0)
        [self decryptFiles:encs];
    
    if(sigs != nil && sigs.count != 0)
        [self verifyFiles:sigs];
    
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}


#pragma mark -
#pragma mark GPG-Helper

// It appears all importKey.. functions were disabled over how libmacgpg handles importing,
// but apperently GPGAccess handles this identically.
- (void)importKeyFromData:(NSData*)data {
	GPGController* gpgc = [[[GPGController alloc] init] autorelease];
    
    NSString* importText = nil;
	@try {
        importText = [gpgc importFromData:data fullImport:NO];
        
        if (gpgc.error)
            @throw gpgc.error;
	} @catch(GPGException* ex) {
        [self displayOperationFailedNotificationWithTitle:[ex reason] 
                                                  message:[ex description]];
        return;
	} @catch(NSException* ex) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Import failed", nil) 
                                                  message:[ex description]];
        return;
	}

    [self displayOperationFinishedNotificationWithTitle:NSLocalizedString(@"Import result", nil) 
                                                message:importText];
}

- (void)importKey:(NSString *)inputString {
    [self importKeyFromData:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSSet*)myPrivateKeys {
    GPGController* context = [GPGController gpgController];
    
    NSMutableSet* keySet = [NSMutableSet set];
    for(GPGKey* k in [context allKeys]) {
        if(k.secret == YES)
            [keySet addObject:k];
    }
        
    return keySet;
}

+ (NSString *)myPrivateFingerprint {
    return [[GPGOptions sharedOptions] valueInGPGConfForKey:@"default-key"];
}

+ (GPGKey*)myPrivateKey {
	
    NSString* keyID = [GPGServices myPrivateFingerprint];
	if(keyID == nil)
        return nil;
    
    GPGController* controller = [GPGController gpgController];
    
	@try {
        // User's configuration may contain a readable fingerprint containing spaces 
        // (e.g., from gpg --fingerprint), but we must match GPGKey without spaces
        NSString *condensedKey = [keyID stringByReplacingOccurrencesOfString:@" " withString:@""];
        GPGKey* key = [[controller keysForSearchPattern:condensedKey] anyObject];
        return (key && key.secret == YES) ? key : nil;
    } @catch (NSException* s) {
    }
    
    return nil;
}

#pragma mark -
#pragma mark Validators

+ (KeyValidatorT)canEncryptValidator {
    KeyValidatorT block = ^(GPGKey* key) {
        if ([key canAnyEncrypt] && key.status < GPGKeyStatus_Invalid)
            return YES;
        return NO;
    };
    
    return [[block copy] autorelease];
}

+ (KeyValidatorT)canSignValidator {
    KeyValidatorT block = ^(GPGKey* key) {
        if ([key canAnySign] && key.status < GPGKeyStatus_Invalid)
            return YES;
        return NO;
    };
    
    return [[block copy] autorelease];
}

+ (KeyValidatorT)isActiveValidator {
    KeyValidatorT block = ^(GPGKey* key) {
        
        // Secret keys are never marked as revoked! Use public key
        key = [key primaryKey];

        if (![key expired] && 
            ![key revoked] && 
            ![key invalid] && 
            ![key disabled]) {
            return YES;
        }
        
        for (GPGSubkey *aSubkey in [key subkeys]) {
            if (![aSubkey expired] && 
                ![aSubkey revoked] && 
                ![aSubkey invalid] && 
                ![aSubkey disabled]) {
                return YES;
            }
        }
        return NO;
    };
    
    return [[block copy] autorelease];
}

#pragma mark -
#pragma mark Text Stuff

-(NSString *)myFingerprint {
    KeyChooserWindowController* wc = [[[KeyChooserWindowController alloc] init] autorelease];
    GPGKey* chosenKey = wc.selectedKey;
    
    if(chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            chosenKey = nil;
        
    }
    
    if(chosenKey != nil) {
        NSString* fp = [[[chosenKey fingerprint] copy] autorelease];
        NSMutableArray* arr  = [NSMutableArray arrayWithCapacity:10];
        NSUInteger fpLength = [fp length];
        // expect 40-length string; breaking into 10 4-char chunks
        const int blkSize = 4;
        for(NSUInteger pos = 0; pos < fpLength; pos += blkSize) {
            NSUInteger nSize = MIN(fpLength - pos, blkSize);
            [arr addObject:[fp substringWithRange:NSMakeRange(pos, nSize)]];
        }
        return [arr componentsJoinedByString:@" "];
    } 
      
    return nil;
}


-(NSString *)myKey {
    KeyChooserWindowController* wc = [[[KeyChooserWindowController alloc] init] autorelease];
    GPGKey* selectedPrivateKey = wc.selectedKey;
    
    if(selectedPrivateKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
        
        if([wc runModal] == 0) 
            selectedPrivateKey = wc.selectedKey;
        else
            selectedPrivateKey = nil;
        
    }
    
    if(selectedPrivateKey == nil)
        return nil;
    
    GPGController* ctx = [GPGController gpgController];
    ctx.useArmor = YES;
    ctx.useTextMode = YES; //Propably not needed
    
    @try {
        NSData* keyData = [ctx exportKeys:[NSArray arrayWithObject:selectedPrivateKey] allowSecret:NO fullExport:NO];
        
        if(keyData == nil) {
            NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"Could not export key %@", @"arg:shortKeyID"), 
                             [selectedPrivateKey shortKeyID]];
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Export failed", nil) 
                                                      message:msg];            
            return nil;
        } else {
            return [[[NSString alloc] initWithData:keyData 
                                          encoding:NSUTF8StringEncoding] autorelease];
        }
	} @catch(NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Export failed", nil)
                                                  message:localException.reason];
	}
    
	return nil;
}


-(NSString *)encryptTextString:(NSString *)inputString {
    GPGController* ctx = [GPGController gpgController];
	ctx.trustAllKeys = YES;
    ctx.useArmor = YES;
    
	RecipientWindowController* rcp = [[RecipientWindowController alloc] init];
	int ret = [rcp runModal];
    [rcp autorelease]; 
	if(ret != 0)
		return nil;  // User pressed 'cancel'

    NSData* inputData = [inputString UTF8Data];
    NSArray* validRecipients = rcp.selectedKeys;
    GPGKey* privateKey = rcp.selectedPrivateKey;
    
    if(rcp.encryptForOwnKeyToo && privateKey) {
        validRecipients = [[[NSSet setWithArray:validRecipients] 
                            setByAddingObject:privateKey] 
                           allObjects];
    } else {
        validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
    }
	
	GPGEncryptSignMode mode = (rcp.sign ? GPGSign : 0) | (validRecipients.count ? GPGPublicKeyEncrypt : 0) | (rcp.symetricEncryption ? GPGSymetricEncrypt : 0);
    
    if(rcp.encryptForOwnKeyToo && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption canceled", nil) 
                                                  message:NSLocalizedString(@"No private key selected to add to recipients", nil)];
        return nil;
    }
    if(rcp.sign && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption canceled", nil) 
                                                  message:NSLocalizedString(@"No private key selected for signing", nil)];
        return nil;
    }
    
    if(validRecipients.count == 0 && !rcp.symetricEncryption) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)
                                                  message:NSLocalizedString(@"No valid recipients found", nil)];
        return nil;
    }
    if (mode == 0) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)
                                                  message:NSLocalizedString(@"Nothing to do", nil)];
        return nil;
    }

    
    @try {
        if(mode & GPGSign)
            [ctx addSignerKey:[privateKey description]];
        
        NSData* outputData = [ctx processData:inputData 
                          withEncryptSignMode:mode
                                   recipients:validRecipients
                             hiddenRecipients:nil];

        if (ctx.error) 
			@throw ctx.error;

        return [outputData gpgString];
        
    } @catch(GPGException* localException) {
        [self displayOperationFailedNotificationWithTitle:[localException reason]  
                                                  message:[localException description]];
        return nil;
    } @catch(NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)  
                                                  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
        /*
        switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
        {
            case GPGErrorNoData:
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)  
                                                          message:NSLocalizedString(@"No encryptable text was found within the selection", nil)];
                break;
            case GPGErrorCancelled:
                break;
            default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)  
                                                          message:GPGErrorDescription(error)];
            }
        }
        */
        return nil;
    } 

    
	return nil;
}


-(NSString *)decryptTextString:(NSString *)inputString
{
	GPGController* ctx = [GPGController gpgController];
    ctx.trustAllKeys = YES;
    ctx.useArmor = YES;
    
    NSData* outputData = nil;
    
	@try {
        outputData = [ctx decryptData:[inputString UTF8Data]];

        if (ctx.error) 
			@throw ctx.error;
	} @catch (GPGException* localException) {
        [self displayOperationFailedNotificationWithTitle:[localException reason]
                                                  message:[localException description]];
        
        return nil;
	} @catch (NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Decryption failed", nil)
                                                  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
        
        return nil;
	} 
    
	//return [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
    return [outputData gpgString];
}

-(NSString *)signTextString:(NSString *)inputString
{
	GPGController* ctx = [GPGController gpgController];
    ctx.useArmor = YES;

	NSData* inputData = [inputString UTF8Data];

    KeyChooserWindowController* wc = [[[KeyChooserWindowController alloc] init] autorelease];
    GPGKey* chosenKey = wc.selectedKey;
    
    if(chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {        
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            chosenKey = nil;
        
    } 

    if(chosenKey != nil)
        [ctx addSignerKey:[chosenKey description]];
    else
        return nil;
    
	@try {
        NSData* outputData = [ctx processData:inputData withEncryptSignMode:GPGClearSign recipients:nil hiddenRecipients:nil];

        if (ctx.error) 
			@throw ctx.error;

        return [outputData gpgString];
	} @catch(GPGException* localException) {
        [self displayOperationFailedNotificationWithTitle:[localException reason]
                                                  message:[localException description]];
        return nil;
	} @catch(NSException* localException) {
        /*
        NSString* errorMessage = nil;
        switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
        {
            case GPGErrorNoData:
                errorMessage = NSLocalizedString(@"No signable text was found within the selection", nil);
                break;
            case GPGErrorBadPassphrase:
                errorMessage = NSLocalizedString(@"The passphrase is incorrect", nil);
                break;
            case GPGErrorUnusableSecretKey:
                errorMessage = NSLocalizedString(@"The default secret key is unusable", nil);
                break;
            case GPGErrorCancelled:
                break;
            default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                errorMessage = GPGErrorDescription(error);
            }
        }
         */
        NSString* errorMessage = [[[localException userInfo] valueForKey:@"gpgTask"] errText];
        if(errorMessage != nil) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Signing failed", nil) 
                                                      message:errorMessage];
        }
        
        return nil;
	}
    
	return nil;
}

-(void)verifyTextString:(NSString *)inputString
{
    GPGController* ctx = [GPGController gpgController];
    ctx.useArmor = YES;
    
	@try {
        NSArray* sigs = [ctx verifySignature:[inputString UTF8Data] originalData:nil];

        if([sigs count] == 0) {
            NSString *retry1 = [inputString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
            sigs = [ctx verifySignature:[retry1 UTF8Data] originalData:nil];
            if([sigs count] == 0) {
                NSString *retry2 = [inputString stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
                sigs = [ctx verifySignature:[retry2 UTF8Data] originalData:nil];
            }
        }
        if([sigs count] > 0) {
            GPGSignature* sig = [sigs objectAtIndex:0];
            GPGErrorCode status = sig.status;
            GPGDebugLog(@"sig.status: %i", status);
            if ([GrowlApplicationBridge isGrowlRunning]) {
                [self growlVerificationResultsFor:NSLocalizedString(@"Selection", nil) signatures:sigs];
            }
            else if([sig status] == GPGErrorNoError) {
                [self displaySignatureVerificationForSig:sig];
            } else {
                NSString* errorMessage = nil;
                switch(status) {
                    case GPGErrorBadSignature:
                        errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Bad signature by %@", @"arg:userID"), 
                                                                                    sig.userID]; 
                        break;
                    default: 
                        errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Unexpected GPG signature status %i", @"arg:GPGSignature status"), status ]; 
                        break;  // I'm unsure if GPGErrorDescription should cover these signature errors
                }
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed", nil)
                                                          message:errorMessage];
            }
        } else {
            //Looks like sigs.count == 0 when we have encrypted text but no signature
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed", nil) 
                                                      message:NSLocalizedString(@"No signatures found within the selection", nil)];
        }
        
	} @catch(NSException* localException) {
        NSLog(@"localException: %@", [localException userInfo]);

        //TODO: Implement correct error handling (might be a problem on libmacgpg's side)
        if([[[localException userInfo] valueForKey:@"errorCode"] intValue] != GPGErrorNoError)
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed", nil) 
                                                      message:[localException description]];
        
        /*
        if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed", nil) 
                                                      message:NSLocalizedString(@"No verifiable text was found within the selection", nil)];
        else {
            GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed", nil) 
                                                      message:GPGErrorDescription(error)];
        }
         */
	} 
}

#pragma mark -
#pragma mark File Stuff

- (NSString *)describeOperationForFiles:(NSArray *)files 
                          singleFileFmt:(NSString *)singleFmt 
                         pluralFilesFmt:(NSString *)pluralFmt 
{
    NSUInteger fcount = [files count];
    if (fcount == 1) {
        NSString *quotedName = [NSString stringWithFormat:@"'%@'",
                                [[[files lastObject] lastPathComponent] 
                                 stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
        return [NSString stringWithFormat:singleFmt, quotedName];
    }
    return [NSString stringWithFormat:pluralFmt, fcount];
}

- (NSString *)describeCompletionForFiles:(NSArray *)files 
                            successCount:(NSUInteger)successCount
                         singleFileFmt:(NSString *)singleFmt 
                         singleFailFmt:(NSString *)singleFailFmt
                        pluralFilesFmt:(NSString *)pluralFmt
{
    NSUInteger totalCount = [files count];
    if (successCount == 1 && totalCount == 1) {
        NSString *quotedName = [NSString stringWithFormat:@"'%@'",
                                [[[files lastObject] lastPathComponent] 
                                 stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
        return [NSString stringWithFormat:singleFmt, quotedName];
    }
    if (successCount == 0 && totalCount == 1) {
        NSString *quotedName = [NSString stringWithFormat:@"'%@'",
                                [[[files lastObject] lastPathComponent] 
                                 stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
        return [NSString stringWithFormat:singleFailFmt, quotedName];
    }
    return [NSString stringWithFormat:pluralFmt, successCount, totalCount];
}

- (NSString*)normalizedAndUniquifiedPathFromPath:(NSString*)path {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    if([fmgr isWritableFileAtPath:[path stringByDeletingLastPathComponent]]) {
        return [ZKArchive uniquify:path];
    } else {
        NSString* desktop = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory,
                                                                 NSUserDomainMask, YES) objectAtIndex:0];
        return [ZKArchive uniquify:[desktop stringByAppendingPathComponent:[path lastPathComponent]]];
    }
}

- (unsigned long long)sizeOfFile:(NSString*)file {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];

    if([fmgr fileExistsAtPath:file]) {
        NSError* err = nil;
        NSDictionary* fileDictionary = [fmgr attributesOfItemAtPath:file error:&err];
        
        if([fileDictionary valueForKey:NSFileType] == NSFileTypeSymbolicLink) {
            NSString* destFile = [fmgr destinationOfSymbolicLinkAtPath:file error:&err];
            
            if(!err) {
                fileDictionary = [fmgr attributesOfItemAtPath:destFile error:&err];
            } else {
                NSLog(@"error with symbolic link in folderSize: %@", [err description]);
                err = nil;
            }
        }
        
        if(err)
            NSLog(@"error in folderSize: %@", [err description]);
        else
            return [[fileDictionary valueForKey:NSFileSize] unsignedLongLongValue];
    }
    
    return 0;
}

- (NSNumber*)folderSize:(NSString *)folderPath {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    NSArray *filesArray = [fmgr subpathsOfDirectoryAtPath:folderPath error:nil];
    NSEnumerator *filesEnumerator = [filesArray objectEnumerator];
    NSString *fileName = nil;
    unsigned long long int fileSize = 0;
    
    while((fileName = [filesEnumerator nextObject]) != nil) {
        fileName = [folderPath stringByAppendingPathComponent:fileName];
        
        fileSize += [self sizeOfFile:fileName];
    }
    
    return [NSNumber numberWithUnsignedLongLong:fileSize];
}

- (NSNumber*)sizeOfFiles:(NSArray*)files {
    __block unsigned long long size = 0;
    
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    [files enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* file = (NSString*)obj;
        BOOL isDirectory = NO;
        BOOL exists = [fmgr fileExistsAtPath:file isDirectory:&isDirectory];
        if(exists && isDirectory)
            size += [[self folderSize:file] unsignedLongLongValue];
        else if(exists) 
            size += [self sizeOfFile:file];
        }];
    
    return [NSNumber numberWithUnsignedLongLong:size];
}

- (NSString*)detachedSignFileWrapped:(ServiceWrappedArgs *)wrappedArgs file:(NSString *)file withKeys:(NSArray *)keys {
    @try {
        GPGController* ctx = [GPGController gpgController];
        ctx.useArmor = YES;
        wrappedArgs.worker.runningController = ctx;

        for(GPGKey* k in keys)
            [ctx addSignerKey:[k description]];

        GPGStream* dataToSign = nil;

        if([[self isDirectoryPredicate] evaluateWithObject:file]) {
            ZipOperation* zipOperation = [[[ZipOperation alloc] init] autorelease];
            zipOperation.filePath = file;
            [zipOperation start];
            
            //Rename file to <dirname>.zip
            file = [self normalizedAndUniquifiedPathFromPath:[file stringByAppendingPathExtension:@"zip"]];
            if([zipOperation.zipData writeToFile:file atomically:YES] == NO)
                return nil;
            
            dataToSign = [GPGFileStream fileStreamForReadingAtPath:file];
        } else {
            dataToSign = [GPGFileStream fileStreamForReadingAtPath:file];
        }

        if (!dataToSign) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Could not read file", nil)
                                                      message:file];
            return nil;
        }
        
        // write to a temporary location in the target directory
        NSError *error = nil;
        GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
                                 [file stringByAppendingString:tempTemplate]
                                                       suffixLen:suffixLen error:&error];
        if (error) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Could not write to directory", nil)
                                                      message:[file stringByDeletingLastPathComponent]];
            return nil;
        }
        
        GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];
        [ctx processTo:output data:dataToSign withEncryptSignMode:GPGDetachedSign recipients:nil hiddenRecipients:nil];

        // check after an operation
        if (wrappedArgs.worker.amCanceling)
            return nil;

        if (ctx.error) 
			@throw ctx.error;

        if ([output length]) {
            [output close];
            [tempFile closeFile];
            
            NSString* sigFile = [file stringByAppendingPathExtension:@"sig"];
            sigFile = [self normalizedAndUniquifiedPathFromPath:sigFile];
            
            error = nil;
            [[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:sigFile error:&error];
            if(!error) {
                tempFile.shouldDeleteFileOnDealloc = NO;
                return sigFile;
            }

            NSLog(@"error while writing to output: %@", error);
            [tempFile deleteFile];
        }
        else {
            [output close];
            [tempFile deleteFile];
        }
    } @catch (GPGException* e) {
        if([GrowlApplicationBridge isGrowlRunning]) {//This is in a loop, so only display Growl...
            NSString *msg = [NSString stringWithFormat:@"%@\n\n%@", [file lastPathComponent], e];
            [self displayOperationFailedNotificationWithTitle:[e reason] message:msg];
        }
    } @catch (NSException* e) {
        if([GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Signing failed", nil)
                                                      message:[file lastPathComponent]];  // no e.reason?
    }

    return nil;
}

- (void)signFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(signFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = [self describeOperationForFiles:files 
                                                 singleFileFmt:NSLocalizedString(@"Signing %@", @"arg:filename") 
                                                pluralFilesFmt:NSLocalizedString(@"Signing %u files", @"arg:count")];
    [_inProgressCtlr addObjectToServiceWorkerArray:worker];
    [_inProgressCtlr showWindow:nil];
    [worker start:files];
}

- (void)signFilesSync:(ServiceWrappedArgs *)wrappedArgs {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self signFilesWrapped:wrappedArgs];
    [pool release];
}

- (void)signFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
    // files, though autoreleased, is safe here even when called async 
    // because it's retained by ServiceWrappedArgs
    NSArray *files = wrappedArgs.arg1;
    if ([files count] < 1)
        return;

    // check before starting an operation
    if (wrappedArgs.worker.amCanceling)
        return;

    KeyChooserWindowController* wc = [[[KeyChooserWindowController alloc] init] autorelease];
    GPGKey* chosenKey = wc.selectedKey;
        
    if(chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
        if([wc runModal] == 0) // thread-safe
            chosenKey = wc.selectedKey;
        else
            return;
    } 
    
    if(chosenKey != nil) {
        NSMutableArray *signedFiles = [NSMutableArray arrayWithCapacity:[files count]];
        
        for(NSString* file in files) {
            // check before starting an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            NSString* sigFile = [self detachedSignFileWrapped:wrappedArgs 
                                                         file:file withKeys:[NSArray arrayWithObject:chosenKey]];

            // check after an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            if(sigFile != nil)
                [signedFiles addObject:file];
        }

        NSUInteger innCount = [files count];
        NSUInteger outCount = [signedFiles count];        
        NSString *title = (innCount == outCount
                           ? NSLocalizedString(@"Signing finished", nil)
                           : (outCount > 0
                              ? NSLocalizedString(@"Signing finished (partially)", nil)
                              : NSLocalizedString(@"Signing failed", nil)));
        NSString *message = [self describeCompletionForFiles:files 
                                                successCount:outCount
                                               singleFileFmt:NSLocalizedString(@"Signed %@", @"arg:filename")
                                               singleFailFmt:NSLocalizedString(@"Failed signing %@", @"arg:filename")
                                              pluralFilesFmt:NSLocalizedString(@"Signed %1$u of %2$u files", @"arg1:successCount; arg2:totalCount")];
        [self displayOperationFinishedNotificationWithTitle:title message:message];
    }
}

- (void)encryptFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(encryptFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = [self describeOperationForFiles:files 
                                                 singleFileFmt:NSLocalizedString(@"Encrypting %@", @"arg:filename") 
                                                pluralFilesFmt:NSLocalizedString(@"Encrypting %u files", @"arg:count")];    
    [_inProgressCtlr addObjectToServiceWorkerArray:worker];
    [_inProgressCtlr showWindow:nil];
    [worker start:files];
}

- (void)encryptFilesSync:(ServiceWrappedArgs *)wrappedArgs {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self encryptFilesWrapped:wrappedArgs];
    [pool release];
}

- (void)encryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
    // files, though autoreleased, is safe here even when called async 
    // because it's retained by ServiceWrappedArgs
    NSArray *files = wrappedArgs.arg1;
    if(files.count == 0)
        return;

    GPGDebugLog(@"encrypting file(s): %@...", [files componentsJoinedByString:@","]);
    
    RecipientWindowController* rcp = [[[RecipientWindowController alloc] init] autorelease];
	int ret = [rcp runModal]; // thread-safe
	if(ret != 0)
		return;  // User pressed 'cancel'
	

	
	NSArray* validRecipients = rcp.selectedKeys;
    GPGKey* privateKey = rcp.selectedPrivateKey;
    
    if(rcp.encryptForOwnKeyToo && privateKey) {
        validRecipients = [[[NSSet setWithArray:validRecipients] 
                            setByAddingObject:privateKey] 
                           allObjects];
    } else {
        validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
    }
	
	GPGEncryptSignMode mode = (rcp.sign ? GPGSign : 0) | (validRecipients.count ? GPGPublicKeyEncrypt : 0) | (rcp.symetricEncryption ? GPGSymetricEncrypt : 0);
    
    if (rcp.encryptForOwnKeyToo && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption canceled", nil) 
                                                  message:NSLocalizedString(@"No private key selected to add to recipients", nil)];
        return;
    }
    if (rcp.sign && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption canceled", nil) 
                                                  message:NSLocalizedString(@"No private key selected for signing", nil)];
        return;
    }
    if (validRecipients.count == 0 && !rcp.symetricEncryption) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)
                                                  message:NSLocalizedString(@"No valid recipients found", nil)];
        return;
    }
    if (mode == 0) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", nil)
                                                  message:NSLocalizedString(@"Nothing to do", nil)];
        return;
    }
	
	
	
    // check before starting an operation
    if (wrappedArgs.worker.amCanceling)
        return;

    NSMutableArray *encryptedFiles = [NSMutableArray arrayWithCapacity:[files count]];
    NSMutableArray *errorMsgs = [NSMutableArray array];
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    BOOL defaultIsArmor = [[GPGOptions sharedOptions] boolForKey:@"armor"];
    BOOL emitVersion = [[GPGOptions sharedOptions] boolForKey:@"emit-version"];

    for (NSString *file in files) 
    {
        @try
        {
            typedef GPGStream*(^DataProvider)();
            DataProvider dataProvider = nil;
            
            long double megabytes = 0;
            NSString* destination = nil;
            BOOL isDirectory = YES;
            BOOL useArmor = NO; // only single-files when "armor" is set in .conf
            
            if (! [fmgr fileExistsAtPath:file isDirectory:&isDirectory]) 
                continue;
            if(isDirectory) {
                NSString* filename = [NSString stringWithFormat:@"%@.zip.gpg", [file lastPathComponent]];
                megabytes = [[self folderSize:file] unsignedLongLongValue] / kBytesInMB;
                destination = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
                dataProvider = ^{
                    ZipOperation* operation = [[[ZipOperation alloc] init] autorelease];
                    operation.filePath = file;
                    operation.delegate = self;
                    [operation start];
                    
                    return [GPGMemoryStream memoryStreamForReading:operation.zipData];
                };
            } else {
                useArmor = defaultIsArmor;
                NSString *fileExtension = useArmor ? @"asc" : @"gpg";
                NSNumber* fileSize = [self sizeOfFiles:[NSArray arrayWithObject:file]];
                megabytes = [fileSize unsignedLongLongValue] / kBytesInMB;
                destination = [file stringByAppendingFormat:@".%@", fileExtension];
                dataProvider = ^{
                    return [GPGFileStream fileStreamForReadingAtPath:file];
                };
            }  
            
            GPGDebugLog(@"fileSize: %@Mb", [NSNumber numberWithDouble:megabytes]);        
            
            // check before starting an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            GPGController* ctx = [GPGController gpgController];
            wrappedArgs.worker.runningController = ctx;
            ctx.useArmor = useArmor;
            ctx.printVersion = emitVersion;
            ctx.useDefaultComments = YES;
            GPGStream* gpgData = nil;
            if(dataProvider != nil)
                gpgData = dataProvider();

            // write to a temporary location in the target directory
            NSError *error = nil;
            GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
                                     [destination stringByAppendingString:tempTemplate]
                                                           suffixLen:suffixLen error:&error];
            if (error) {
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Could not write to directory", nil)
                                                          message:[destination stringByDeletingLastPathComponent]];
                return;
            }

            GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];
            
            if(mode == GPGEncryptSign && privateKey != nil)
                [ctx addSignerKey:[privateKey description]];

            [ctx processTo:output data:gpgData withEncryptSignMode:mode recipients:validRecipients hiddenRecipients:nil];

            // check after a lengthy operation
            if (wrappedArgs.worker.amCanceling)
                return;
            
            if (ctx.error) 
                @throw ctx.error;

            //Check if directory is writable and append i+1 if file already exists at destination
            destination = [self normalizedAndUniquifiedPathFromPath:destination];    
            GPGDebugLog(@"destination: %@", destination);
            
            [output close];
            [tempFile closeFile];
            error = nil;
            [[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:destination error:&error];
            if(error != nil) {
                NSLog(@"error while renaming file: %@", error);
                [tempFile deleteFile];
                NSString *msg = [NSString stringWithFormat:
                                 NSLocalizedString(@"Failed renaming to %@", @"arg:filename"),
                                 [destination lastPathComponent]];
                [errorMsgs addObject:msg];
            }
            else {
                tempFile.shouldDeleteFileOnDealloc = NO;
                [encryptedFiles addObject:file];
            }

        } @catch(NSException* ex) {
            NSString *msg;
            if ([ex isKindOfClass:[GPGException class]]) {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
            }
            else {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], 
                       NSLocalizedString(@"Unexpected encrypt error", nil)];
                NSLog(@"encryptData ex: %@", ex);
            }
            
            [errorMsgs addObject:msg];
        }
    }

    NSUInteger innCount = [files count];
    NSUInteger outCount = [encryptedFiles count];        
    NSString *title = (innCount == outCount
                       ? NSLocalizedString(@"Encryption finished", nil)
                       : (outCount > 0
                          ? NSLocalizedString(@"Encryption finished (partially)", nil)
                          : NSLocalizedString(@"Encryption failed", nil)));
    NSMutableString *message = [NSMutableString stringWithString:
                                [self describeCompletionForFiles:files 
                                                    successCount:outCount 
                                                   singleFileFmt:NSLocalizedString(@"Encrypted %@", @"arg:filename") 
                                                   singleFailFmt:NSLocalizedString(@"Failed encrypting %@", @"arg:filename")
                                                  pluralFilesFmt:NSLocalizedString(@"Encrypted %1$u of %2$u files", @"arg1:successCount arg2:totalCount")]];
    if ([errorMsgs count]) {
        [message appendString:@"\n\n"];
        [message appendString:[errorMsgs componentsJoinedByString:@"\n"]];
    }
    [self displayOperationFinishedNotificationWithTitle:title message:message];
}

- (void)decryptFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(decryptFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = [self describeOperationForFiles:files 
                                                 singleFileFmt:NSLocalizedString(@"Decrypting %@", @"arg:filename") 
                                                pluralFilesFmt:NSLocalizedString(@"Decrypting %u files", @"arg:count")];    
    [_inProgressCtlr addObjectToServiceWorkerArray:worker];
    [_inProgressCtlr showWindow:nil];
    [worker start:files];
}

- (void)decryptFilesSync:(ServiceWrappedArgs *)wrappedArgs {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self decryptFilesWrapped:wrappedArgs];
    [pool release];
}

- (void)decryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
    // files, though autoreleased, is safe here even when called async 
    // because it's retained by ServiceWrappedArgs
    NSArray *files = wrappedArgs.arg1;
    if ([files count] < 1)
        return;

    GPGController* ctx = [GPGController gpgController];
    wrappedArgs.worker.runningController = ctx;
    
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    NSMutableArray *decryptedFiles = [NSMutableArray arrayWithCapacity:[files count]];
    NSMutableArray *errorMsgs = [NSMutableArray array];

    // has thread-safe methods as used here
    DummyVerificationController* dummyController = nil;

    for(NSString* file in files) {
        // check before starting an operation
        if (wrappedArgs.worker.amCanceling)
            return;

        BOOL isDirectory = NO;
        @try {
            if([fmgr fileExistsAtPath:file isDirectory:&isDirectory] &&
               isDirectory == NO) {                
                GPGFileStream *input = [GPGFileStream fileStreamForReadingAtPath:file];
                GPGDebugLog(@"inputData.size: %llu", [input length]);

                // write to a temporary location in the target directory
                NSError *error = nil;
                GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
                                         [file stringByAppendingString:tempTemplate]
                                                               suffixLen:suffixLen error:&error];
                if (error) {
                    [self displayOperationFailedNotificationWithTitle:
                     NSLocalizedString(@"Could not write to directory", nil)
                                                              message:[file stringByDeletingLastPathComponent]];
                    return;
                }

                GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];
                [ctx decryptTo:output data:input];

                // check again after a potentially long operation
                if (wrappedArgs.worker.amCanceling)
                    return;
                
                if ([output length]) {
                    [output close];
                    [tempFile closeFile];

                    error = nil;
                    NSString* outputFile = [self normalizedAndUniquifiedPathFromPath:[file stringByDeletingPathExtension]];
                    [[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:outputFile error:&error];
                    if(error != nil) {
                        NSLog(@"error while renaming file: %@", error);
                        [tempFile deleteFile];
                        NSString *msg = [NSString stringWithFormat:
                                         NSLocalizedString(@"Failed renaming to %@", @"arg:filename"),
                                         [outputFile lastPathComponent]];
                        [errorMsgs addObject:msg];
                    }
                    else {
                        tempFile.shouldDeleteFileOnDealloc = NO;
                        [decryptedFiles addObject:file];
                    }
                }
                else {
                    [output close];
                    [tempFile deleteFile];
                }

                if (ctx.error) 
                    @throw ctx.error;

                //
                // Show any signatures encountered
                //
                if ([GrowlApplicationBridge isGrowlRunning]) {
                    if ([ctx.signatures count] > 0)
                        [self growlVerificationResultsFor:file signatures:ctx.signatures];
                }
                else if(ctx.signatures && ctx.signatures.count > 0) {
                    GPGDebugLog(@"found signatures: %@", ctx.signatures);

                    if(dummyController == nil) {
                        dummyController = [[DummyVerificationController alloc]
                                           initWithWindowNibName:@"VerificationResultsWindow"];
                        [dummyController showWindow:self]; // now thread-safe
                        dummyController.isActive = YES; // now thread-safe
                    }
                    
                    for(GPGSignature* sig in ctx.signatures) {
                        [dummyController addResultFromSig:sig forFile:file];
                    }
                } else if(dummyController != nil) {
                    //Add a line to mention that the file isn't signed
                    [dummyController addResults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                 [file lastPathComponent], @"filename",
                                                 NSLocalizedString(@"No signatures found", nil), @"verificationResult",
                                                 nil]];
                
                }
            }
        } @catch(NSException* ex) {
            NSString *msg;
            if ([ex isKindOfClass:[GPGException class]]) {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
            }
            else {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], 
                       NSLocalizedString(@"Unexpected decrypt error", nil)];
                NSLog(@"decryptData ex: %@", ex);
            }
 
            [errorMsgs addObject:msg];
        } 
    }
    
    dummyController.isActive = NO;

    NSUInteger innCount = [files count];
    NSUInteger outCount = [decryptedFiles count];        
    NSString *title = (innCount == outCount
                       ? NSLocalizedString(@"Decryption finished", nil)
                       : (outCount > 0
                          ? NSLocalizedString(@"Decryption finished (partially)", nil)
                          : NSLocalizedString(@"Decryption failed", nil)));
    NSMutableString *message = [NSMutableString stringWithString:
                                [self describeCompletionForFiles:files 
                                                    successCount:outCount 
                                                   singleFileFmt:NSLocalizedString(@"Decrypted %@", @"arg:filename") 
                                                   singleFailFmt:NSLocalizedString(@"Failed decrypting %@", @"arg:filename")
                                                  pluralFilesFmt:NSLocalizedString(@"Decrypted %1$u of %2$u files", @"arg1:successCount arg2:totalCount")]];
    if ([errorMsgs count]) {
        [message appendString:@"\n\n"];
        [message appendString:[errorMsgs componentsJoinedByString:@"\n"]];
    }
    [self displayOperationFinishedNotificationWithTitle:title message:message];

    [dummyController runModal]; // thread-safe
    [dummyController release];
}
 
- (void)verifyFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(verifyFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = [self describeOperationForFiles:files 
                                                 singleFileFmt:NSLocalizedString(@"Verifying signature of %@", @"arg:filename") 
                                                pluralFilesFmt:NSLocalizedString(@"Verifying signatures of %u files", @"arg:count")];
    [_inProgressCtlr addObjectToServiceWorkerArray:worker];
    [_inProgressCtlr showWindow:nil];
    [worker start:files];
}

- (void)verifyFilesSync:(ServiceWrappedArgs *)wrappedArgs {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self verifyFilesWrapped:wrappedArgs];
    [pool release];
}

- (void)verifyFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
    // files, though autoreleased, is safe here even when called async 
    // because it's retained by NSOperation that is wrapping the process
    NSArray *files = wrappedArgs.arg1;

    NSMutableSet *filesInVerification = [NSMutableSet set];
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];

    // has thread-safe methods as used here
    DummyVerificationController* fvc = nil;
    if ([GrowlApplicationBridge isGrowlRunning] == NO) {
        fvc = [[[DummyVerificationController alloc]
                initWithWindowNibName:@"VerificationResultsWindow"] autorelease];
        [fvc showWindow:self]; // now thread-safe
        fvc.isActive = YES; // now thread-safe
    }
    
    for (NSString* serviceFile in files) {
        // check before operation
        if (wrappedArgs.worker.amCanceling)
            return;
        
        //Do the file stuff here to be able to check if file is already in verification
        NSString* signedFile = serviceFile;
        NSString* signatureFile = [FileVerificationController searchSignatureFileForFile:signedFile];
        if (signatureFile == nil) {
            signatureFile = serviceFile;
            signedFile = [FileVerificationController searchFileForSignatureFile:signatureFile];
        }
        if (signedFile == nil) {
            signedFile = serviceFile;
            signatureFile = nil;
        }
        
        if(signatureFile != nil) {
            if([filesInVerification containsObject:signatureFile]) 
                continue;

            //Probably a problem with restarting of validation when files are missing
            [filesInVerification addObject:signatureFile];
        }
        
        NSException* firstException = nil;
        NSException* secondException = nil;
        
        NSArray* sigs = nil;
        
        if([fmgr fileExistsAtPath:signedFile] && [fmgr fileExistsAtPath:signatureFile]) {
            @try {
                GPGController* ctx = [GPGController gpgController];
                wrappedArgs.worker.runningController = ctx;

                GPGFileStream *signatureInput = [GPGFileStream fileStreamForReadingAtPath:signatureFile];
                GPGFileStream *originalInput = [GPGFileStream fileStreamForReadingAtPath:signedFile];
                sigs = [ctx verifySignatureOf:signatureInput originalData:originalInput];
            } @catch (NSException *exception) {
                firstException = exception;
                sigs = nil;
            }

            // check after operation
            if (wrappedArgs.worker.amCanceling)
                return;
        }
        
        //Try to verify the file itself without a detached sig
        if(sigs == nil || sigs.count == 0) {
            @try {
                GPGController* ctx = [GPGController gpgController];
                wrappedArgs.worker.runningController = ctx;

                GPGFileStream *signedInput = [GPGFileStream fileStreamForReadingAtPath:serviceFile];
                sigs = [ctx verifySignatureOf:signedInput originalData:nil];

            } @catch (NSException *exception) {
                secondException = exception;
                sigs = nil;
            }

            // check after operation
            if (wrappedArgs.worker.amCanceling)
                return;
        }

        if ([GrowlApplicationBridge isGrowlRunning]) {
            [self growlVerificationResultsFor:serviceFile signatures:sigs];
        }
        else if(sigs != nil) {
            if(sigs.count == 0) {
                id verificationResult = nil; //NSString or NSAttributedString
                verificationResult = NSLocalizedString(@"Verification FAILED: No signatures found", nil);
                
                NSColor* bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                
                NSRange range = [verificationResult rangeOfString:NSLocalizedString(@"FAILED", @"Matched in \"Verification FAILED:\"")];
                verificationResult = [[NSMutableAttributedString alloc] 
                                      initWithString:verificationResult];
                
                if (range.location != NSNotFound) {
                    [verificationResult addAttribute:NSFontAttributeName 
                                               value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                                               range:range];
                    [verificationResult addAttribute:NSBackgroundColorAttributeName 
                                               value:bgColor
                                               range:range];
                }
                
                NSDictionary* result = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [signedFile lastPathComponent], @"filename",
                                        verificationResult, @"verificationResult", 
                                        nil];
                [fvc addResults:result];
                [verificationResult release];
            } else if(sigs.count > 0) {
                for(GPGSignature* sig in sigs) {
                    [fvc addResultFromSig:sig forFile:signedFile];
                }
            }
        } else {
            [fvc addResults:[NSDictionary dictionaryWithObjectsAndKeys:
                             [signedFile lastPathComponent], @"filename",
                             NSLocalizedString(@"No verifiable data found", nil), @"verificationResult",
                             nil]];
        }
    }

    [fvc runModal]; // thread-safe
}

- (void)growlVerificationResultsFor:(NSString *)file signatures:(NSArray *)signatures 
{
    if ([GrowlApplicationBridge isGrowlRunning] != YES)
        return;

    NSString *title = [self describeOperationForFiles:[NSArray arrayWithObject:file] 
                                        singleFileFmt:NSLocalizedString(@"Verification for %@", @"arg:filename") 
                                       pluralFilesFmt:NSLocalizedString(@"Verification for %u files", @"arg:count")];
    NSMutableString *summary = [NSMutableString string];
    if ([signatures count] > 0) {
        for (GPGSignature *gpgSig in signatures) {
            [summary appendFormat:@"%@\n", [gpgSig humanReadableDescription]];
        }
    }
    else {
        [summary appendString:NSLocalizedString(@"No signatures found", nil)];
    }
    
    [self displayOperationFinishedNotificationWithTitle:title message:summary];
}

//Skip fixing this for now. We need better handling of imports in libmacgpg.
/*
- (void)importKeyFromData:(NSData*)data {
	GPGController* ctx = [[[GPGController alloc] init] autorelease];
    
    NSString* importText = nil;
	@try {
        importText = [ctx importFromData:data fullImport:NO];
	} @catch(GPGException* ex) {
        [self displayOperationFailedNotificationWithTitle:[ex reason] 
                                                  message:[ex description]];
        return;
	}
    
    [[NSAlert alertWithMessageText:NSLocalizedString(@"Import result", nil)
                     defaultButton:nil
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:importText]
     runModal];
}
*/

 
- (void)importFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(importFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = [self describeOperationForFiles:files 
                                                 singleFileFmt:NSLocalizedString(@"Importing %@", @"arg:filename") 
                                                pluralFilesFmt:NSLocalizedString(@"Importing %u files", @"arg:count")];
    [_inProgressCtlr addObjectToServiceWorkerArray:worker];
    [_inProgressCtlr showWindow:nil];
    [worker start:files];
}

- (void)importFilesSync:(ServiceWrappedArgs *)wrappedArgs {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [self importFilesWrapped:wrappedArgs];
    [pool release];
}

- (void)importFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
    // files, though autoreleased, is safe here even when called async 
    // because it's retained by ServiceWrappedArgs
    NSArray *files = wrappedArgs.arg1;
    if ([files count] < 1)
        return;

	GPGController* gpgc = [GPGController gpgController];
	wrappedArgs.worker.runningController = gpgc;

    NSMutableArray *importedFiles = [NSMutableArray arrayWithCapacity:[files count]];
    NSMutableArray *errorMsgs = [NSMutableArray array];
    
    for(NSString* file in files) {
        // check before starting an operation
        if (wrappedArgs.worker.amCanceling)
            return;

        if([[self isDirectoryPredicate] evaluateWithObject:file] == YES) {
            NSString *msg = [NSString stringWithFormat:NSLocalizedString(@"%@ — Cannot import directory", @"arg:path"), 
                             [file lastPathComponent]];
            [errorMsgs addObject:msg];
            continue; 
        }

        NSData* data = [NSData dataWithContentsOfFile:file];
        @try {
            /*NSString* inputText = */[gpgc importFromData:data fullImport:NO];

            // check after an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            if (gpgc.error) 
                @throw gpgc.error;

            [importedFiles addObject:file];

        } @catch(NSException* ex) {
            NSString *msg;
            if ([ex isKindOfClass:[GPGException class]]) {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
            }
            else {
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], 
                       NSLocalizedString(@"Unexpected import error", nil)];
                NSLog(@"importFromData ex: %@", ex);
            }            
            [errorMsgs addObject:msg];
        }
    }

    NSUInteger innCount = [files count];
    NSUInteger outCount = [importedFiles count];        
    NSString *title = (innCount == outCount
                       ? NSLocalizedString(@"Import finished", nil)
                       : (outCount > 0
                          ? NSLocalizedString(@"Import finished (partially)", nil)
                          : NSLocalizedString(@"Import failed", nil)));
    NSMutableString *message = [NSMutableString stringWithString:
                                [self describeCompletionForFiles:files 
                                                    successCount:outCount
                                                   singleFileFmt:NSLocalizedString(@"Imported %@", @"arg:filename") 
                                                   singleFailFmt:NSLocalizedString(@"Failed importing %@", @"arg:filename")
                                                  pluralFilesFmt:NSLocalizedString(@"Imported %1$u of %2$u files", @"arg1:successCount arg2:totalCount")]];
    if ([errorMsgs count]) {
        [message appendString:@"\n\n"];
        [message appendString:[errorMsgs componentsJoinedByString:@"\n"]];
    }
    [self displayOperationFinishedNotificationWithTitle:title message:message];
}

#pragma mark - ServiceWorkerDelegate

- (void)workerWasCanceled:(id)worker {
    [self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)workerDidFinish:(id)worker {    
    [self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)removeWorker:(id)worker 
{
    [_inProgressCtlr removeObjectFromServiceWorkerArray:worker];
    if ([_inProgressCtlr.serviceWorkerArray count] < 1)
        [_inProgressCtlr.window orderOut:nil];
}
     
#pragma mark - NSPredicates for filtering file arrays

- (NSPredicate*)fileExistsPredicate {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    return [[[NSPredicate predicateWithBlock:^BOOL(id file, NSDictionary *bindings) {
        return [file isKindOfClass:[NSString class]] && [fmgr fileExistsAtPath:file];
    }] copy] autorelease];
}

- (NSPredicate*)isDirectoryPredicate {
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    return [[[NSPredicate predicateWithBlock:^BOOL(id file, NSDictionary *bindings) {
        BOOL isDirectory = NO;
        return ([file isKindOfClass:[NSString class]] && 
                [fmgr fileExistsAtPath:file isDirectory:&isDirectory] &&
                isDirectory);
    }] copy] autorelease];
}

#pragma mark -
#pragma mark Service handling routines

-(void)dealWithPasteboard:(NSPasteboard *)pboard
                 userData:(NSString *)userData
                     mode:(ServiceModeEnum)mode
                    error:(NSString **)error {
	[self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
    
    NSString *pboardString = nil, *pbtype = nil;
	if(mode!=MyKeyService && mode!=MyFingerprintService)
	{
		pbtype = [pboard availableTypeFromArray:[NSArray arrayWithObjects:
                                                         NSPasteboardTypeString, 
                                                         NSPasteboardTypeRTF,
                                                         nil]];
        NSString *myerror = NSLocalizedString(@"GPGServices did not get usable data from the pasteboard.", @"Pasteboard could not supply the string in an acceptible format.");
        
        if([pbtype isEqualToString:NSPasteboardTypeString])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error = myerror;
				[self goneIn60Seconds];
				return;
			}
		}
		else if([pbtype isEqualToString:NSPasteboardTypeRTF])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error = myerror;
				[self goneIn60Seconds];
				return;
			}
		}
		else
		{
			*error = myerror;
			[self goneIn60Seconds];
			return;
		}
	}
    
    NSString *newString=nil;
	switch(mode)
	{
		case SignService:
			newString=[self signTextString:pboardString];
			break;
	    case EncryptService:
	        newString=[self encryptTextString:pboardString];
			break;
	    case DecryptService:
	        newString=[self decryptTextString:pboardString];
			break;
		case VerifyService:
			[self verifyTextString:pboardString];
			break;
		case MyKeyService:
			newString=[self myKey];
			break;
		case MyFingerprintService:
			newString=[self myFingerprint];
			break;
		case ImportKeyService:
			[self importKey:pboardString];
			break;
        default:
            break;
	}
    
	BOOL shouldExitServiceRequest = YES;
	
	if (newString != nil) {
        static NSString * const kServiceShowInWindow = @"showInWindow";
        if ([userData isEqualToString:kServiceShowInWindow]) {
			[SimpleTextWindow showText:newString withTitle:@"GPGServices" andDelegate:self];
			shouldExitServiceRequest = NO;
        }
        else {
            [pboard clearContents];
			
			NSMutableArray *pbitems = [NSMutableArray array];
			
			if ([pbtype isEqualToString:NSPasteboardTypeHTML]) {        
				NSPasteboardItem *htmlItem = [[[NSPasteboardItem alloc] init] autorelease];
				[htmlItem setString:[newString stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"] 
							forType:NSPasteboardTypeHTML];
				[pbitems addObject:htmlItem];
			}
			else if ([pbtype isEqualToString:NSPasteboardTypeRTF]) {        
				NSPasteboardItem *rtfItem = [[[NSPasteboardItem alloc] init] autorelease];
				[rtfItem setString:newString forType:NSPasteboardTypeRTF];
				[pbitems addObject:rtfItem];
			}
			else {
				NSPasteboardItem *stringItem = [[[NSPasteboardItem alloc] init] autorelease];
				[stringItem setString:newString forType:NSPasteboardTypeString];            
				[pbitems addObject:stringItem];
			}
			
			[pboard writeObjects:pbitems];

        }
	}
    
	if (shouldExitServiceRequest) {
		[self goneIn60Seconds];
	}
}

-(void)dealWithFilesPasteboard:(NSPasteboard *)pboard
                      userData:(NSString *)userData
                          mode:(FileServiceModeEnum)mode
                         error:(NSString **)error {
    [self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
    
    NSData *data = [pboard dataForType:NSFilenamesPboardType];
    
    NSString* fileErrorStr = nil;
    NSArray *filenames = [NSPropertyListSerialization
                          propertyListFromData:data
                          mutabilityOption:kCFPropertyListImmutable
                          format:nil
                          errorDescription:&fileErrorStr];
    if(fileErrorStr) {
        NSLog(@"error while getting files form pboard: %@", fileErrorStr);
        *error = fileErrorStr;
    } else {
        switch(mode) {
            case SignFileService:
                [self signFiles:filenames];
                break;
            case EncryptFileService:
                [self encryptFiles:filenames];
                break;
            case DecryptFileService:
                [self decryptFiles:filenames];
                break;
            case VerifyFileService:
                [self verifyFiles:filenames];
                break;
            case ImportFileService:
                [self importFiles:filenames];
                break;
        }
    }
    
    [self goneIn60Seconds];
}


-(void)sign:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:SignService error:error];}

-(void)encrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:EncryptService error:error];}

-(void)decrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:DecryptService error:error];}

-(void)verify:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:VerifyService error:error];}

-(void)myKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:MyKeyService error:error];}

-(void)myFingerprint:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:MyFingerprintService error:error];}

-(void)importKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithPasteboard:pboard userData:userData mode:ImportKeyService error:error];}

-(void)signFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error 
{[self dealWithFilesPasteboard:pboard userData:userData mode:SignFileService error:error];}

-(void)encryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithFilesPasteboard:pboard userData:userData mode:EncryptFileService error:error];}

-(void)decryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error 
{[self dealWithFilesPasteboard:pboard userData:userData mode:DecryptFileService error:error];}

-(void)validateFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithFilesPasteboard:pboard userData:userData mode:VerifyFileService error:error];}

-(void)importFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error
{[self dealWithFilesPasteboard:pboard userData:userData mode:ImportFileService error:error];}

#pragma mark -
#pragma mark UI Helpher

- (NSURL*)getFilenameForSavingWithSuggestedPath:(NSString*)path 
                         withSuggestedExtension:(NSString*)ext {    
    NSSavePanel* savePanel = [NSSavePanel savePanel];
    savePanel.title = NSLocalizedString(@"Choose Destination", @"for saving a file");
    savePanel.directory = [path stringByDeletingLastPathComponent];
    
    if(ext == nil)
        ext = @".gpg";
    [savePanel setNameFieldStringValue:[[path lastPathComponent] 
                                        stringByAppendingString:ext]];
    
    if([savePanel runModal] == NSFileHandlingPanelOKButton)
        return savePanel.URL;
    else
        return nil;
}


-(void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body {
    [[NSAlert alertWithMessageText:title
                     defaultButton:nil
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:[NSString stringWithFormat:@"%@", body]] runModalOnMain];
}

- (void)displayOperationFinishedNotificationWithTitle:(NSString*)title message:(NSString*)body {
    [self performSelectorOnMainThread:@selector(displayOperationFinishedNotificationWithTitleOnMain:) 
                           withObject:[NSArray arrayWithObjects:title, body, nil] 
                        waitUntilDone:NO];
}

// called by displayOperationFinishedNotificationWithTitle:message:
- (void)displayOperationFinishedNotificationWithTitleOnMain:(NSArray *)args {
    NSString *title = [args objectAtIndex:0]; 
    NSString *body = [args objectAtIndex:1];
    if([GrowlApplicationBridge isGrowlRunning]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:body
                               notificationName:gpgGrowlOperationSucceededName
                                       iconData:nil
                                       priority:0
                                       isSticky:NO
                                   clickContext:NULL];
    } else {
        [self displayMessageWindowWithTitleText:title bodyText:body];
    }
}

- (void)displayOperationFailedNotificationWithTitle:(NSString*)title message:(NSString*)body {
    [self performSelectorOnMainThread:@selector(displayOperationFailedNotificationWithTitleOnMain:)
                           withObject:[NSArray arrayWithObjects:title, body, nil]
                        waitUntilDone:NO];
}

// called by displayOperationFailedNotificationWithTitle:message:
- (void)displayOperationFailedNotificationWithTitleOnMain:(NSArray *)args {
    NSString *title = [args objectAtIndex:0]; 
    NSString *body = [args objectAtIndex:1];
    if([GrowlApplicationBridge isGrowlRunning]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:body
                               notificationName:gpgGrowlOperationFailedName
                                       iconData:nil
                                       priority:0
                                       isSticky:NO
                                   clickContext:NULL];
    } else {
        [self displayMessageWindowWithTitleText:title bodyText:body];
    }
}

- (void)displaySignatureVerificationForSig:(GPGSignature*)sig {
    [self performSelectorOnMainThread:@selector(displaySignatureVerificationForSigOnMain:) 
                           withObject:sig 
                        waitUntilDone:NO];
}

// called by displaySignatureVerificationForSig:
- (void)displaySignatureVerificationForSigOnMain:(GPGSignature*)sig {
    /*
    GPGContext* aContext = [[[GPGContext alloc] init] autorelease];
    NSString* userID = [[aContext keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
    NSString* validity = [sig validityDescription];
    */
    
    NSString* userID = [sig userID];
    NSString* validity = [GPGKey validityDescription:[sig trust]];
    
    [[NSAlert alertWithMessageText:NSLocalizedString(@"Verification successful", nil)
                     defaultButton:nil
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:NSLocalizedString(@"Good signature (%@ trust):\n\"%@\"", @"arg1:validity arg2:userID"),
                                                     validity,userID]
     runModal];
}

/*
-(NSString *)context:(GPGContext *)context passphraseForKey:(GPGKey *)key again:(BOOL)again
{
	[passphraseText setStringValue:@""];
	int flag=[NSApp runModalForWindow:passphraseWindow];
	NSString *passphrase=[[[passphraseText stringValue] copy] autorelease];
	[passphraseWindow close];
	if(flag)
		return passphrase;
	else
		return nil;
}
*/

- (IBAction)closeModalWindow:(id)sender {
	[NSApp stopModalWithCode:[sender tag]];
}

- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow {
	[self goneIn60Seconds];
}

//
//Timer based application termination
//
- (void)cancelTerminateTimer {
	terminateCounter++;
	[currentTerminateTimer invalidate];
	currentTerminateTimer = nil;
}

- (void)goneIn60Seconds {
	terminateCounter--;
	if (currentTerminateTimer != nil) {
		//Shouldn't happen.
		[self cancelTerminateTimer];
		terminateCounter--;
	}
	if (terminateCounter <= 0) {
		terminateCounter = 0;
		[NSApp hide:self];
		currentTerminateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(selfQuit:) userInfo:nil repeats:YES];
	}
}

- (void)selfQuit:(NSTimer *)timer {
    if ([_inProgressCtlr.serviceWorkerArray count] < 1) {
        [self cancelTerminateTimer];
        [NSApp terminate:self];
    }
}

@end
