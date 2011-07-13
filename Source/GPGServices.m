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

#import "ZipOperation.h"
#import "ZipKit/ZKArchive.h"
#import "NSPredicate+negate.h"

#define SIZE_WARNING_LEVEL_IN_MB 10

@implementation GPGServices

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[NSApp setServicesProvider:self];
    //	NSUpdateDynamicServices();
	currentTerminateTimer=nil;
    
    [GrowlApplicationBridge setGrowlDelegate:self];
}

/*
- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    if([[filename pathExtension] isEqualToString:@"gpg"]) {
        NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
        
        [self decryptFiles:[NSArray arrayWithObject:filename]];
        
        [pool release];
    }
    
	return NO;
}
 */

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    NSArray* encs = [filenames pathsMatchingExtensions:[NSArray arrayWithObject:@"gpg"]];
    NSArray* sigs = [filenames pathsMatchingExtensions:[NSArray arrayWithObjects:@"sig", @"asc", nil]];
    
    if(encs != nil && encs.count != 0)
        [self decryptFiles:encs];
    
    if(sigs != nil && sigs.count != 0)
        [self verifyFiles:sigs];
    
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
    
    [pool release];
}


#pragma mark -
#pragma mark GPG-Helper

- (void)importKeyFromData:(NSData*)data {
    NSDictionary *importedKeys = nil;
	GPGContext *aContext = [[GPGContext alloc] init];
    
    GPGData* inputData = [[GPGData alloc] initWithDataNoCopy:data];
    
	@try {
        importedKeys = [aContext importKeyData:inputData];
	} @catch(NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Import failed:", nil)
                                                  message:GPGErrorDescription([[[localException userInfo] 
                                                                                objectForKey:@"GPGErrorKey"]                                                              intValue])];
        return;
	} @finally {
        [inputData release];
        [aContext release];
    }
    
    [[NSAlert alertWithMessageText:NSLocalizedString(@"Import result:", @"Alert box import result message text")
                     defaultButton:NSLocalizedString(@"Ok", nil)
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:NSLocalizedString(@"%i key(s), %i secret key(s), %i revocation(s)", 
                                                     @"alert-box informative"),
      [[importedKeys valueForKey:@"importedKeyCount"] intValue],
      [[importedKeys valueForKey:@"importedSecretKeyCount"] intValue],
      [[importedKeys valueForKey:@"newRevocationCount"] intValue]]
     runModal];
}

- (void)importKey:(NSString *)inputString {
    [self importKeyFromData:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSSet*)myPrivateKeys {
    GPGContext* context = [[GPGContext alloc] init];
    
    NSMutableSet* keySet = [NSMutableSet set];
    for(GPGKey* k in [NSSet setWithArray:[[context keyEnumeratorForSearchPattern:@"" secretKeysOnly:YES] allObjects]]) {
        [keySet addObject:[context refreshKey:k]];
    }
    
    [context release];
    
    return keySet;
}

+ (GPGKey*)myPrivateKey {
    GPGOptions *myOptions = [[[GPGOptions alloc] init] autorelease];
	NSString *keyID = [myOptions optionValueForName:@"default-key"];
    
	@try {
        GPGContext *aContext = [[[GPGContext alloc] init] autorelease];
        
        GPGKey* returnKey = nil;
        if(keyID != nil) {
            returnKey = [aContext keyFromFingerprint:keyID secretKey:YES];
        } 
        
        if(keyID == nil || returnKey == nil) {
            //return nil if more than one private key is set and more than one key available
            if([[self myPrivateKeys] count] > 1) 
                return nil;
            
            returnKey = [[aContext keyEnumeratorForSearchPattern:@"" secretKeysOnly:YES] nextObject];
        }
        
        return returnKey;
    } @catch (NSException* s) {
        
    } 
    
    return nil;
}


#pragma mark -
#pragma mark Validators

+ (KeyValidatorT)canEncryptValidator {
    id block = ^(GPGKey* key) {
        // A subkey can be expired, without the key being, thus making key useless because it has
        // no other subkey...
        // We don't care about ownerTrust, validity
        
        for (GPGSubkey *aSubkey in [key subkeys]) {
            if ([aSubkey canEncrypt] && 
                ![aSubkey hasKeyExpired] && 
                ![aSubkey isKeyRevoked] &&
                ![aSubkey isKeyInvalid] &&
                ![aSubkey isKeyDisabled]) {
                return YES;
            }
        }
        return NO;
    };
    
    return [[block copy] autorelease];
}


+ (KeyValidatorT)canSignValidator {
    // Copied from GPGMail's GPGMailBundle.m
    KeyValidatorT block =  ^(GPGKey* key) {
        // A subkey can be expired, without the key being, thus making key useless because it has
        // no other subkey...
        // We don't care about ownerTrust, validity, subkeys
        
        // Secret keys are never marked as revoked! Use public key
        key = [key publicKey];
        
        // If primary key itself can sign, that's OK (unlike what gpgme documentation says!)
        if ([key canSign] && 
            ![key hasKeyExpired] && 
            ![key isKeyRevoked] && 
            ![key isKeyInvalid] && 
            ![key isKeyDisabled]) {
            return YES;
        }
        
        for (GPGSubkey *aSubkey in [key subkeys]) {
            if ([aSubkey canSign] && 
                ![aSubkey hasKeyExpired] && 
                ![aSubkey isKeyRevoked] && 
                ![aSubkey isKeyInvalid] && 
                ![aSubkey isKeyDisabled]) {
                return YES;
            }
        }
        return NO;
    };
    
    return [[block copy] autorelease];
}

+ (KeyValidatorT)isActiveValidator {
    // Copied from GPGMail's GPGMailBundle.m
    KeyValidatorT block =  ^(GPGKey* key) {
        
        // Secret keys are never marked as revoked! Use public key
        key = [key publicKey];
        
        // If primary key itself can sign, that's OK (unlike what gpgme documentation says!)
        if (![key hasKeyExpired] && 
            ![key isKeyRevoked] && 
            ![key isKeyInvalid] && 
            ![key isKeyDisabled]) {
            return YES;
        }
        
        for (GPGSubkey *aSubkey in [key subkeys]) {
            if (![aSubkey hasKeyExpired] && 
                ![aSubkey isKeyRevoked] && 
                ![aSubkey isKeyInvalid] && 
                ![aSubkey isKeyDisabled]) {
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
    GPGKey* chosenKey = [GPGServices myPrivateKey];
    
    NSSet* availableKeys = [[GPGServices myPrivateKeys] filteredSetUsingPredicate:
                            [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices isActiveValidator]((GPGKey*)evaluatedObject);
    }]];
    
    if(availableKeys.count == 0) {
        [self showNoPrivateKeyErrorMessage]; return nil;
    } else if(chosenKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
        [wc setKeyValidator:[GPGServices isActiveValidator]];
        
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            chosenKey = nil;
        
        [wc release];
    }
    
    if(chosenKey != nil)
        return [[[chosenKey formattedFingerprint] copy] autorelease];
    else
        return nil;
}


-(NSString *)myKey {
    GPGKey* selectedPrivateKey = [GPGServices myPrivateKey];
    
    NSSet* availableKeys = [[GPGServices myPrivateKeys] filteredSetUsingPredicate:
                            [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices isActiveValidator]((GPGKey*)evaluatedObject);
    }]];
    
    if(availableKeys.count == 0) {
        [self showNoPrivateKeyErrorMessage]; return nil;
    } else if(selectedPrivateKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
        [wc setKeyValidator:[GPGServices isActiveValidator]];
        
        if([wc runModal] == 0) 
            selectedPrivateKey = wc.selectedKey;
        else
            selectedPrivateKey = nil;
        
        [wc release];
    }
    
    if(selectedPrivateKey == nil)
        return nil;
    
    GPGContext* ctx = [[GPGContext alloc] init];
    [ctx setUsesArmor:YES];
    [ctx setUsesTextMode:YES];
    
    NSData* keyData = nil;
    @try {
        keyData = [[ctx exportedKeys:[NSArray arrayWithObject:selectedPrivateKey]] data];
        
        if(keyData == nil) {
            [[NSAlert alertWithMessageText:NSLocalizedString(@"Exporting key failed.", @"exporting key error message text")
                             defaultButton:NSLocalizedString(@"Ok", nil)
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:NSLocalizedString(@"Could not export key %@", @"export key alert box informative text"),
              [selectedPrivateKey shortKeyID]] 
             runModal];
            
            return nil;
        }
	} @catch(NSException* localException) {
        GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
        [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Exporting key failed", @"key export failed title")
                                                  message:GPGErrorDescription(error)];
        return nil;
	} @finally {
        [ctx release];
    }
    
	return [[[NSString alloc] initWithData:keyData 
                                  encoding:NSUTF8StringEncoding] autorelease];
}

-(NSString *)encryptTextString:(NSString *)inputString
{
    GPGContext *aContext = [[GPGContext alloc] init];
    [aContext setUsesArmor:YES];
    
	BOOL trustsAllKeys = YES;
    GPGData *outputData = nil;
    
	RecipientWindowController* rcp = [[RecipientWindowController alloc] init];
	int ret = [rcp runModal];
    [rcp release];
	if(ret != 0) {
		[aContext release];
		return nil;
	} else {
		GPGData *inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
		
		BOOL sign = rcp.sign;
        NSArray* validRecipients = rcp.selectedKeys;
        GPGKey* privateKey = rcp.selectedPrivateKey;
        
        if(rcp.encryptForOwnKeyToo && privateKey) {
            validRecipients = [[[NSSet setWithArray:validRecipients] 
                                setByAddingObject:[privateKey publicKey]] 
                               allObjects];
        } else {
            validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
        }
        
        if(privateKey == nil) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed.", @"operation failed title")
                                           message:NSLocalizedString(@"No usable private key found", @"operation failed message")];
            [inputData release];
            [aContext release];
            return nil;
        }
        
        if(validRecipients.count == 0) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed.", @"operation failed title")
                                                      message:NSLocalizedString(@"No valid recipients found", 
                                                                                @"operation failed message")];
            
            [inputData release];
            [aContext release];
            return nil;
        }
        
		@try {
            if(sign) {
                [aContext addSignerKey:privateKey];
                outputData=[aContext encryptedSignedData:inputData withKeys:validRecipients trustAllKeys:trustsAllKeys];
            } else {
                outputData=[aContext encryptedData:inputData withKeys:validRecipients trustAllKeys:trustsAllKeys];
            }
		} @catch(NSException* localException) {
            outputData = nil;
            switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
            {
                case GPGErrorNoData:
                    [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed.", @"operation failed title")
                                                              message:NSLocalizedString(@"No encryptable text was found within the selection.",
                                                                                        @"operation failed message")];
                    break;
                case GPGErrorCancelled:
                    break;
                default: {
                    GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                    [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed.", @"operation failed title")
                                                              message:GPGErrorDescription(error)];
                }
            }
            return nil;
		} @finally {
            [inputData release];
            [aContext release];
        }
	}
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}

-(NSString *)decryptTextString:(NSString *)inputString
{
    GPGData *outputData = nil;
	GPGContext *aContext = [[GPGContext alloc] init];
    
	GPGData *inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    
	@try {
     	[aContext setPassphraseDelegate:self];
        outputData = [aContext decryptedData:inputData];
	} @catch (NSException* localException) {
        outputData = nil;
        switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
        {
            case GPGErrorNoData:
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Decryption failed.", @"operation failed title")
                                                          message:NSLocalizedString(@"No decryptable text was found within the selection.", @"operation failed message")];
                break;
            case GPGErrorCancelled:
                break;
            default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Decryption failed.", @"operation failed title")
                                                          message:GPGErrorDescription(error)];
            }
        }
        return nil;
	} @finally {
        [inputData release];
        [aContext release];
    }
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}


-(NSString *)signTextString:(NSString *)inputString
{
	GPGContext *aContext = [[GPGContext alloc] init];
	[aContext setPassphraseDelegate:self];
    
	GPGData *inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    GPGKey* chosenKey = [GPGServices myPrivateKey];
    
    NSSet* availableKeys = [[GPGServices myPrivateKeys] filteredSetUsingPredicate:
                            [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices canSignValidator]((GPGKey*)evaluatedObject);
    }]];
    
    if(availableKeys.count == 0) {
        [self showNoPrivateKeyErrorMessage]; return nil;
    } else if(chosenKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
        [wc setKeyValidator:[GPGServices canSignValidator]];
        
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            chosenKey = nil;
        
        [wc release];
    } else if(availableKeys.count == 1) {
        chosenKey = [availableKeys anyObject];
    }
    
    if(chosenKey != nil) {
        [aContext clearSignerKeys];
        [aContext addSignerKey:chosenKey];
    } else {
        [inputData release];
        [aContext release];
        
        return nil;
    }
    
    GPGData *outputData = nil;
	@try {
        outputData = [aContext signedData:inputData signatureMode:GPGSignatureModeClear];
	} @catch(NSException* localException) {
        outputData = nil;
        NSString* errorMessage = nil;
        switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
        {
            case GPGErrorNoData:
                errorMessage = NSLocalizedString(@"No signable text was found within the selection.", @"operation failed message");
                break;
            case GPGErrorBadPassphrase:
                errorMessage = NSLocalizedString(@"The passphrase is incorrect.", @"operation failed message");
                break;
            case GPGErrorUnusableSecretKey:
                errorMessage = NSLocalizedString(@"The default secret key is unusable.", @"operation failed message");
                break;
            case GPGErrorCancelled:
                break;
            default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                errorMessage = GPGErrorDescription(error);
            }
        }
        
        if(errorMessage != nil)
            [self displayMessageWindowWithTitleText:NSLocalizedString(@"Signing failed.", @"operation failed title")
                                           bodyText:errorMessage];
        
        return nil;
	} @finally {
        [inputData release];
        [aContext release];
    }
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}


-(void)verifyTextString:(NSString *)inputString
{
	GPGContext *aContext = [[GPGContext alloc] init];
    GPGData* inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

    [aContext setUsesTextMode:YES];
    
	@try {
        NSArray* sigs = [aContext verifySignedData:inputData originalData:nil];
        
        if([sigs count]>0)
        {
            GPGSignature* sig=[sigs objectAtIndex:0];
            if(GPGErrorCodeFromError([sig status])==GPGErrorNoError) {
                [self displaySignatureVerificationForSig:sig];
            } else {
                NSString* failedString = NSLocalizedString(@"FAILED", @"'FAILED' translated. Needed to colorize the in the results window");
                NSString* title = [NSString stringWithFormat:NSLocalizedString(@"Verification %@.", @"operation failed title"),
                                   failedString];
                [self displayOperationFailedNotificationWithTitle:title
                                                          message:GPGErrorDescription([sig status])];
            }
        }
        else {
            //Looks like sigs.count == 0 when we have encrypted text but no signature
            //[self displayMessageWindowWithTitleText:@"Verification error."
            //                               bodyText:@"Unable to verify due to an internal error"];
            
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed.", @"operation failed title")
                                                      message:NSLocalizedString(@"No signatures found within the selection.",
                                                                                @"operation failed message")];
        }
        
	} @catch(NSException* localException) {
        if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed.", @"operation failed title")
                                                      message:NSLocalizedString(@"No verifiable text was found within the selection", 
                                                                                @"operation failed message")];
        else {
            GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Verification failed.", @"operation failed title")
                                                      message:GPGErrorDescription(error)];
        }
        return;
	} @finally {
        [inputData release];
        [aContext release];
    }
}

#pragma mark -
#pragma mark File Stuff

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

- (NSString*)detachedSignFile:(NSString*)file withKeys:(NSArray*)keys {
    @try {
        //Generate .sig file
        GPGContext* signContext = [[[GPGContext alloc] init] autorelease];
        [signContext setUsesArmor:YES];
        for(GPGKey* k in keys)
            [signContext addSignerKey:k];
        
        GPGData* dataToSign = nil;
        if([[self isDirectoryPredicate] evaluateWithObject:file]) {
            ZipOperation* zipOperation = [[[ZipOperation alloc] init] autorelease];
            zipOperation.filePath = file;
            [zipOperation start];
            
            //Rename file to <dirname>.zip
            file = [self normalizedAndUniquifiedPathFromPath:[file stringByAppendingPathExtension:@"zip"]];
            if([zipOperation.zipData writeToFile:file atomically:YES] == NO)
                return nil;
            
            dataToSign = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
        } else {
            dataToSign = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
        }
        
        GPGData* signData = [signContext signedData:dataToSign signatureMode:GPGSignatureModeDetach];
        
        NSString* sigFile = [file stringByAppendingPathExtension:@"sig"];
        sigFile = [self normalizedAndUniquifiedPathFromPath:sigFile];
        [[signData data] writeToFile:sigFile atomically:YES];
        
        return sigFile;
    } @catch (NSException* e) {
        if([GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Signing failed", @"operation failed title")
                                                      message:[file lastPathComponent]];
    }
    
    return nil;
}

- (void)signFiles:(NSArray*)files {     
    long double megabytes = [[self sizeOfFiles:files] unsignedLongLongValue] / 1048576.0;
    
    if(megabytes > SIZE_WARNING_LEVEL_IN_MB) {
        int ret = [[NSAlert alertWithMessageText:NSLocalizedString(@"Large File(s)", @"alert-box message text")
                                   defaultButton:NSLocalizedString(@"Continue", nil)
                                 alternateButton:NSLocalizedString(@"Cancel", nil)
                                     otherButton:nil
                       informativeTextWithFormat:NSLocalizedString(@"Encryption will take a long time.\nPress 'Cancel' to abort.",
                                                                   @"alert box informative text")] 
                   runModal];
        
        if(ret == NSAlertAlternateReturn)
            return;
    }
    
    GPGKey* chosenKey = [GPGServices myPrivateKey];
    
    NSSet* availableKeys = [[GPGServices myPrivateKeys] filteredSetUsingPredicate:
                            [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        return [GPGServices canSignValidator]((GPGKey*)evaluatedObject);
    }]];
    
    if(availableKeys.count == 0) {
        [self showNoPrivateKeyErrorMessage]; return;
    } else if(chosenKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[[KeyChooserWindowController alloc] init] autorelease];
        [wc setKeyValidator:[GPGServices canSignValidator]];
        
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            return;
    } else if(availableKeys.count == 1) {
        chosenKey = [availableKeys anyObject];
    }
    
    unsigned int signedFilesCount = 0;
    if(chosenKey != nil) {
        for(NSString* file in files) {
            NSString* sigFile = [self detachedSignFile:file withKeys:[NSArray arrayWithObject:chosenKey]];
            if(sigFile != nil)
                signedFilesCount++;
        }
        
        if(signedFilesCount > 0) {
            [self displayOperationFinishedNotificationWithTitle:NSLocalizedString(@"Signing finished", @"operation finished title")
                                                        message:[NSString 
                                                                 stringWithFormat:NSLocalizedString(@"Finished signing %i file(s)",
                                                                                                    @"operation finished message"), 
                                                                 files.count]];
        }
    }
}

- (GPGData*)signedGPGDataForGPGData:(GPGData*)dataToSign withKeys:(NSArray*)keys {
    @try {
        GPGContext* signContext = [[[GPGContext alloc] init] autorelease];
        for(GPGKey* k in keys)
            [signContext addSignerKey:k];
        
        return [signContext signedData:dataToSign signatureMode:GPGSignatureModeNormal];
    } @catch (NSException* e) {
        NSLog(@"error in signedGPGDataForGPGData: %@", [e description]);
    }
    
    return nil;
}

- (void)encryptFiles:(NSArray*)files {
    BOOL trustAllKeys = YES;
    
    NSLog(@"encrypting file(s): %@...", [files componentsJoinedByString:@","]);
    
    if(files.count == 0)
        return;
    
    RecipientWindowController* rcp = [[[RecipientWindowController alloc] init] autorelease];
	int ret = [rcp runModal];
    
	if(ret != 0) {
        //User pressed 'cancel'
		return;
	} else {
    	BOOL sign = rcp.sign;
        NSArray* validRecipients = rcp.selectedKeys;
        GPGKey* privateKey = rcp.selectedPrivateKey;
        
        if(rcp.encryptForOwnKeyToo && privateKey) {
            validRecipients = [[[NSSet setWithArray:validRecipients] 
                                setByAddingObject:[privateKey publicKey]] 
                               allObjects];
        } else {
            validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
        }
        
        //GPGData* gpgData = nil;
        long double megabytes = 0;
        NSString* destination = nil;
        
        NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
        
        typedef NSData*(^DataProvider)();
        DataProvider dataProvider = nil;
        
        if(files.count == 1) {
            NSString* file = [files objectAtIndex:0];
            BOOL isDirectory = YES;
            BOOL exists = [fmgr fileExistsAtPath:file isDirectory:&isDirectory];
            
            if(exists && isDirectory) {
                NSString* filename = [NSString stringWithFormat:@"%@.zip.gpg", [file lastPathComponent]];
                megabytes = [[self folderSize:file] unsignedLongLongValue] / 1048576.0;
                destination = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
                dataProvider = ^{
                    ZipOperation* operation = [[[ZipOperation alloc] init] autorelease];
                    operation.filePath = file;
                    operation.delegate = self;
                    [operation start];
                    
                    return operation.zipData;
                };
            } else if(exists) {
                NSNumber* fileSize = [self sizeOfFiles:[NSArray arrayWithObject:file]];
                megabytes = [fileSize unsignedLongLongValue] / 1048576;
                destination = [file stringByAppendingString:@".gpg"];
                dataProvider = ^{
                    return (NSData*)[NSData dataWithContentsOfFile:file];
                };
            } else {    
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"File doesn't exist", @"operation failed title")
                                                          message:NSLocalizedString(@"Please try again", @"operation failed message")];
                return;
            }
        } else if(files.count > 1) {
            megabytes = [[self sizeOfFiles:files] unsignedLongLongValue] / 1048576.0;
            destination = [[[files objectAtIndex:0] stringByDeletingLastPathComponent] 
                           stringByAppendingPathComponent:@"Archive.zip.gpg"];
            dataProvider = ^{
                ZipOperation* operation = [[[ZipOperation alloc] init] autorelease];
                operation.files = files;
                operation.delegate = self;
                [operation start];
                
                return operation.zipData;
            };
        }
        
        //Check if directory is writable and append i+1 if file already exists at destination
        destination = [self normalizedAndUniquifiedPathFromPath:destination];
        
        NSLog(@"destination: %@", destination);
        NSLog(@"fileSize: %@Mb", [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithDouble:megabytes]
                                                                  numberStyle:NSNumberFormatterDecimalStyle]);        
        
        if(megabytes > SIZE_WARNING_LEVEL_IN_MB) {
            int ret = [[NSAlert alertWithMessageText:NSLocalizedString(@"Large File(s)", @"alert-box message text")
                                       defaultButton:NSLocalizedString(@"Continue", nil)
                                     alternateButton:NSLocalizedString(@"Cancel", nil)
                                         otherButton:nil
                           informativeTextWithFormat:NSLocalizedString(@"Encryption will take a long time.\nPress 'Cancel' to abort.",
                                                                       @"alert box informative text")] 
                       runModal];
            
            if(ret == NSAlertAlternateReturn)
                return;
        }
        
        NSAssert(dataProvider != nil, @"dataProvider can't be nil");
        NSAssert(destination != nil, @"destination can't be nil");
        
        GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
        GPGData* gpgData = nil;
        if(dataProvider != nil) 
            gpgData = [[[GPGData alloc] initWithData:dataProvider()] autorelease];
        
        GPGData* encrypted = nil;
        if(sign == YES && privateKey != nil) {
            [ctx addSignerKey:privateKey];
            encrypted = [ctx encryptedSignedData:gpgData
                                        withKeys:validRecipients 
                                    trustAllKeys:trustAllKeys];
        } else {
            encrypted = [ctx encryptedData:gpgData 
                                  withKeys:validRecipients
                              trustAllKeys:trustAllKeys];
        }
        
        if(encrypted == nil) {
            [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Encryption failed", @"operation failed title")
                                                      message:[destination lastPathComponent]];
        } else {
            [encrypted.data writeToFile:destination atomically:YES];
            [self displayOperationFinishedNotificationWithTitle:NSLocalizedString(@"Encryption finished", @"operation finished title")
                                                        message:[destination lastPathComponent]];
        }
    }
}


- (void)decryptFiles:(NSArray*)files {
	GPGContext *aContext = [[[GPGContext alloc] init] autorelease];
    [aContext setPassphraseDelegate:self];
    
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    unsigned int decryptedFilesCount = 0;
    
    DummyVerificationController* dummyController = nil;
    
    for(NSString* file in files) {
        BOOL isDirectory = NO;
        @try {
            if([fmgr fileExistsAtPath:file isDirectory:&isDirectory] &&
               isDirectory == NO) {                
                GPGData* inputData = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
                NSLog(@"inputData.size: %lld", [inputData length]);
                
                NSArray* signatures = nil;
                GPGData* outputData = [aContext decryptedData:inputData signatures:&signatures];
                NSString* outputFile = [self normalizedAndUniquifiedPathFromPath:[file stringByDeletingPathExtension]];
                
                NSError* error = nil;
                [outputData.data writeToFile:outputFile options:NSDataWritingAtomic error:&error];
                
                if(error != nil) 
                    NSLog(@"error while writing to output: %@", error);
                else
                    decryptedFilesCount++;
                
                if(signatures && signatures.count > 0) {
                    NSLog(@"found signatures: %@", signatures);

                    if(dummyController == nil) {
                        dummyController = [[DummyVerificationController alloc]
                                           initWithWindowNibName:@"VerificationResultsWindow"];
                        [dummyController showWindow:self];
                        dummyController.isActive = YES;
                    }
                    
                    for(GPGSignature* sig in signatures) {
                        [dummyController addResultFromSig:sig forFile:file];
                    }
                } else if(dummyController != nil) {
                    //Add a line to mention that the file isn't signed
                    [dummyController addResults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                 [file lastPathComponent], @"filename",
                                                 NSLocalizedString(@"No signatures found", @"verficiation result"),@"verificationResult",
                                                 nil]];
                
                }
            }
        } @catch (NSException* localException) {
            switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])) {
                case GPGErrorNoData:
                    [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Decryption failed.", @"operation failed title")
                                                              message:NSLocalizedString(@"No decryptable data was found.", 
                                                                                        @"operation failed message")];
                    break;
                case GPGErrorCancelled:
                    break;
                default: {
                    GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                    [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Decryption failed.", @"operation failed title")
                                                              message:GPGErrorDescription(error)];
                }
            }
        } 
    }
    
    dummyController.isActive = NO;
    
    if(decryptedFilesCount > 0)
        [self displayOperationFinishedNotificationWithTitle:NSLocalizedString(@"Decryption finished", @"operation failed title")
                                                    message:
         [NSString stringWithFormat:NSLocalizedString(@"Finished decrypting %i file(s)", @"operation finished message"), files.count]];
    
    [dummyController runModal];
    [dummyController release];
}


- (void)verifyFiles:(NSArray*)files {
    GPGContext *aContext = [[[GPGContext alloc] init] autorelease];
    [aContext setPassphraseDelegate:self];    
    
    FileVerificationController* fvc = [[FileVerificationController alloc] init];
    fvc.filesToVerify = files;
    [fvc startVerification:nil];
    [fvc runModal];
    [fvc release];
}

- (void)importFiles:(NSArray*)files {
	GPGContext *aContext = [[[GPGContext alloc] init] autorelease];
    
    NSUInteger foundKeysCount = 0; //Track valid key-files
    NSUInteger importedKeyCount = 0;
    NSUInteger importedSecretKeyCount = 0;
    NSUInteger newRevocationCount = 0;
    
    for(NSString* file in files) {
        if([[self isDirectoryPredicate] evaluateWithObject:file] == YES) {
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Can't import keys from directory", 
                                                                                    @"operation failed title")
                                                          message:[file lastPathComponent]];
            continue; //Shortcut all following code, go to next file
        }
        
        GPGData* inputData = [[[GPGData alloc] initWithDataNoCopy:[NSData dataWithContentsOfFile:file]] autorelease];
        
        @try {
            NSDictionary* importResults = [aContext importKeyData:inputData];
            NSDictionary* changedKeys = [importResults valueForKey:GPGChangesKey];
            
            if(changedKeys.count > 0) {
                ++foundKeysCount;
                
                importedKeyCount += [[importResults valueForKey:@"importedKeyCount"] unsignedIntValue];
                importedSecretKeyCount += [[importResults valueForKey:@"importedSecretKeyCount"] unsignedIntValue];
                newRevocationCount += [[importResults valueForKey:@"newRevocationCount"] unsignedIntValue];
            } else if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) { //This is in a loop, so only display Growl... 
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"No importable Keys found", 
                                                                                    @"operation failed title")
                                                          message:[file lastPathComponent]];
            }    
        } @catch(NSException* localException) {
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
                [self displayOperationFailedNotificationWithTitle:NSLocalizedString(@"Import failed:", @"operation failed title")
                                                          message:GPGErrorDescription([[[localException userInfo] 
                                                                                        objectForKey:@"GPGErrorKey"]                                                              intValue])];
        }
    }
    
    //Don't show result window when there were no imported keys
    if(foundKeysCount > 0) {
        [[NSAlert alertWithMessageText:NSLocalizedString(@"Import result:", @"Alert box import result message text")
                         defaultButton:NSLocalizedString(@"Ok", nil)
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:NSLocalizedString(@"%i key(s), %i secret key(s), %i revocation(s)", "alert-box informative"),
          importedKeyCount,
          importedSecretKeyCount,
          newRevocationCount]
         runModal];     
    }
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
        
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    NSString *pboardString = nil;
	if(mode!=MyKeyService && mode!=MyFingerprintService)
	{
		NSString* type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:
                                                         NSPasteboardTypeString, 
                                                         NSPasteboardTypeRTF,
                                                         nil]];
        
        if([type isEqualToString:NSPasteboardTypeString])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error = NSLocalizedString(@"Error: Could not perform GPG operation. Pasteboard could not supply text string.",
                                           @"pasteboard error string");
				[self exitServiceRequest];
				return;
			}
		}
		else if([type isEqualToString:NSPasteboardTypeRTF])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error = NSLocalizedString(@"Error: Could not perform GPG operation. Pasteboard could not supply text string.",
                                           @"pasteboard error string");
				[self exitServiceRequest];
				return;
			}
		}
		else
		{
            //@"Pasteboard could not supply the string in an acceptible format.";
			*error = NSLocalizedString(@"Error: Could not perform GPG operation.",
                                       @"pasteboard error string");
			[self exitServiceRequest];
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
    
	if(newString!=nil) {
        if([userData isEqualToString:@"showInWindow"]) {
            //Use new pasteboard for invoking the show in TextEdit service
            pboard = [NSPasteboard pasteboardWithUniqueName];
        }
        
		[pboard declareTypes:[NSArray arrayWithObjects:NSPasteboardTypeString,NSPasteboardTypeRTF,nil] owner:nil];
		[pboard setString:newString forType:NSPasteboardTypeString];
   		[pboard setString:newString forType:NSPasteboardTypeRTF];
        
        if([userData isEqualToString:@"showInWindow"]) {
            bool ret = NSPerformService(@"New TextEdit Window Containing Selection", pboard);
            if(ret == NO)
                [self displayOperationFailedNotificationWithTitle:@"Fail"
                                                          message:@"Opening TextEdit failed"];
            else
                [self displayOperationFinishedNotificationWithTitle:NSLocalizedString(@"Text opened in TextEdit", 
                                                                                      @"text was opened in textedit") 
                                                            message:NSLocalizedString(@"Please see TextEdit for the result", 
                                                                                      @"text was opened in TextEdit message")];
        }
	}
    
    [pool release];
    
	[self exitServiceRequest];
}

-(void)dealWithFilesPasteboard:(NSPasteboard *)pboard
                      userData:(NSString *)userData
                          mode:(FileServiceModeEnum)mode
                         error:(NSString **)error {
    [self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
    
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
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
    
    [pool release];
    
    [self exitServiceRequest];
}

-(void)exitServiceRequest
{
	[NSApp hide:self];
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
    savePanel.title = NSLocalizedString(@"Choose Destination", @"save-panel title");
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
                     defaultButton:NSLocalizedString(@"Ok", nil)
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:[NSString stringWithFormat:@"%@", body]] runModal];
}

- (void)displayOperationFinishedNotificationWithTitle:(NSString*)title message:(NSString*)body {
    if([GrowlApplicationBridge isGrowlRunning]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:body
                               notificationName:gpgGrowlOperationSucceededName
                                       iconData:[NSData data]
                                       priority:0
                                       isSticky:NO
                                   clickContext:NULL];
    } else {
        [self displayMessageWindowWithTitleText:title bodyText:body];
    }
}

- (void)displayOperationFailedNotificationWithTitle:(NSString*)title message:(NSString*)body {
    if([GrowlApplicationBridge isGrowlRunning]) {
        [GrowlApplicationBridge notifyWithTitle:title
                                    description:body
                               notificationName:gpgGrowlOperationFailedName
                                       iconData:[NSData data]
                                       priority:0
                                       isSticky:NO
                                   clickContext:NULL];
    } else {
        [self displayMessageWindowWithTitleText:title bodyText:body];
    }
}

- (void)displaySignatureVerificationForSig:(GPGSignature*)sig {
    GPGContext* aContext = [[[GPGContext alloc] init] autorelease];
    NSString* userID = [[aContext keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
    NSString* validity = [sig validityDescription];
    
    [[NSAlert alertWithMessageText:NSLocalizedString(@"Verification successful.", @"alert-box message text")
                     defaultButton:NSLocalizedString(@"Ok", nil)
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:NSLocalizedString(@"Good signature (%@ trust):\n\"%@\"", @"alert-box informative"),validity,userID]
     runModal];
}

- (void)showNoPrivateKeyErrorMessage {
    NSInteger ret = [[NSAlert alertWithMessageText:NSLocalizedString(@"No Private-Key found", @"alert-box message text")
                                     defaultButton:NSLocalizedString(@"Ok", nil)
                                   alternateButton:NSLocalizedString(@"Help", nil)
                                       otherButton:nil
                         informativeTextWithFormat:NSLocalizedString(@"No private-key found on your system.\nClick 'Help' to open a web-browser with a tutorial.", @"alert-box informative")]
                     runModal];
    if(ret == NSAlertAlternateReturn) {
        //Open browser with help
        NSString* localizedURLString = NSLocalizedString(@"https://github.com/GPGTools/GPGKeychainAccess/wiki/Getting-started",
                                                         @"URL to a good tutorial about generating keys");
        NSURL* url = [NSURL URLWithString:localizedURLString];
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

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


-(IBAction)closeModalWindow:(id)sender{
	[NSApp stopModalWithCode:[sender tag]];
}

//
//Timer based application termination
//
-(void)cancelTerminateTimer
{
	[currentTerminateTimer invalidate];
	currentTerminateTimer=nil;
}

-(void)goneIn60Seconds
{
	if(currentTerminateTimer!=nil)
		[self cancelTerminateTimer];
	currentTerminateTimer=[NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(selfQuit:) userInfo:nil repeats:NO];
}

-(void)selfQuit:(NSTimer *)timer
{
	[NSApp terminate:self];
}

@end
