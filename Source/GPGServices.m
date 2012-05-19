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

#import "ZipOperation.h"
#import "ZipKit/ZKArchive.h"
#import "NSPredicate+negate.h"
#import "GPGKey+utils.h"
#import "NSAlert+ThreadSafety.h"

#define SIZE_WARNING_LEVEL_IN_MB 10
static const float kBytesInMB = 1.e6; // Apple now uses this vs 2^20

@interface GPGServices ()
- (void)removeWorker:(id)worker;
- (void)displayOperationFinishedNotificationWithTitleOnMain:(NSArray *)args;
- (void)displayOperationFailedNotificationWithTitleOnMain:(NSArray *)args;
- (void)displaySignatureVerificationForSigOnMain:(GPGSignature*)sig;

// expected count = 1; quote lastPathComponent
- (NSString *)quoteOneFilesName:(NSArray *)files;

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
        [self displayOperationFailedNotificationWithTitle:@"Import failed." 
                                                  message:[ex description]];
        return;
	}
    
    [[NSAlert alertWithMessageText:@"Import result:"
                     defaultButton:@"Ok"
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:importText]
     runModal];
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
        NSMutableArray* arr  = [NSMutableArray arrayWithCapacity:8];
        int i = 0;
        for(i = 0; i < 10; ++i) {
            [arr addObject:[fp substringWithRange:NSMakeRange(i*4, 4)]];
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
            [[NSAlert alertWithMessageText:@"Exporting key failed." 
                             defaultButton:@"Ok"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Could not export key %@", [selectedPrivateKey shortKeyID]] 
             runModal];
            
            return nil;
        } else {
            return [[[NSString alloc] initWithData:keyData 
                                          encoding:NSUTF8StringEncoding] autorelease];
        }
	} @catch(NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:@"Exporting key failed"
                                                  message:localException.reason];
	}
    
	return nil;
}


-(NSString *)encryptTextString:(NSString *)inputString
{
    GPGController* ctx = [GPGController gpgController];
	ctx.trustAllKeys = YES;
    ctx.useArmor = YES;
    
	RecipientWindowController* rcp = [[RecipientWindowController alloc] init];
	int ret = [rcp runModal];
    [rcp autorelease]; 
	if(ret != 0)
		return nil;  // User pressed 'cancel'

    NSData* inputData = [inputString UTF8Data];
    GPGEncryptSignMode mode = rcp.sign ? GPGEncryptSign : GPGPublicKeyEncrypt;
    NSArray* validRecipients = rcp.selectedKeys;
    GPGKey* privateKey = rcp.selectedPrivateKey;
    
    if(rcp.encryptForOwnKeyToo && privateKey) {
        validRecipients = [[[NSSet setWithArray:validRecipients] 
                            setByAddingObject:privateKey] 
                           allObjects];
    } else {
        validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
    }
    
    if(rcp.encryptForOwnKeyToo && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption canceled." 
                                                  message:@"No private key selected to add to recipients"];
        return nil;
    }
    if(rcp.sign && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption canceled." 
                                                  message:@"No private key selected for signing"];
        return nil;
    }
    
    if(validRecipients.count == 0) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption failed."
                                                  message:@"No valid recipients found"];
        return nil;
    }
    
    @try {
        if(mode == GPGEncryptSign)
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
        [self displayOperationFailedNotificationWithTitle:@"Encryption failed."  
                                                  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
        /*
        switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
        {
            case GPGErrorNoData:
                [self displayOperationFailedNotificationWithTitle:@"Encryption failed."  
                                                          message:@"No encryptable text was found within the selection."];
                break;
            case GPGErrorCancelled:
                break;
            default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                [self displayOperationFailedNotificationWithTitle:@"Encryption failed."  
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
        [self displayOperationFailedNotificationWithTitle:[localException reason]
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
                errorMessage = @"No signable text was found within the selection.";
                break;
            case GPGErrorBadPassphrase:
                errorMessage = @"The passphrase is incorrect.";
                break;
            case GPGErrorUnusableSecretKey:
                errorMessage = @"The default secret key is unusable.";
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
        if(errorMessage != nil)
            [self displayMessageWindowWithTitleText:@"Signing failed."
                                           bodyText:errorMessage];
        
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
            if([sig status] == GPGErrorNoError) {
                [self displaySignatureVerificationForSig:sig];
            } else {
                NSString* errorMessage = nil;
                switch(status) {
                    case GPGErrorBadSignature:
                        errorMessage = [@"Bad signature by " stringByAppendingString:sig.userID]; break;
                    default: 
                        errorMessage = [NSString stringWithFormat:@"Unexpected gpg signature status %i", status ]; 
                        break;  // I'm unsure if GPGErrorDescription should cover these signature errors
                }
                [self displayOperationFailedNotificationWithTitle:@"Verification FAILED."
                                                          message:errorMessage];
            }
        } else {
            //Looks like sigs.count == 0 when we have encrypted text but no signature
            [self displayOperationFailedNotificationWithTitle:@"Verification failed." 
                                                      message:@"No signatures found within the selection."];
        }
        
	} @catch(NSException* localException) {
        NSLog(@"localException: %@", [localException userInfo]);

        //TODO: Implement correct error handling (might be a problem on libmacgpg's side)
        if([[[localException userInfo] valueForKey:@"errorCode"] intValue] != GPGErrorNoError)
            [self displayOperationFailedNotificationWithTitle:@"Verification failed." 
                                                      message:[ctx.error description]];
        
        /*
        if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
            [self displayOperationFailedNotificationWithTitle:@"Verification failed." 
                                                      message:@"No verifiable text was found within the selection"];
        else {
            GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
            [self displayOperationFailedNotificationWithTitle:@"Verification failed." 
                                                      message:GPGErrorDescription(error)];
        }
         */
	} 
}

#pragma mark -
#pragma mark File Stuff

- (NSString *)quoteOneFilesName:(NSArray *)files {
    return [NSString stringWithFormat:@"'%@'",
            [[[files lastObject] lastPathComponent] stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
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

- (NSString*)detachedSignFile:(NSString*)file withKeys:(NSArray*)keys {
    @try {
        GPGController* ctx = [GPGController gpgController];
        ctx.useArmor = YES;

        for(GPGKey* k in keys)
            [ctx addSignerKey:[k description]];

        NSData* dataToSign = nil;

        if([[self isDirectoryPredicate] evaluateWithObject:file]) {
            ZipOperation* zipOperation = [[[ZipOperation alloc] init] autorelease];
            zipOperation.filePath = file;
            [zipOperation start];
            
            //Rename file to <dirname>.zip
            file = [self normalizedAndUniquifiedPathFromPath:[file stringByAppendingPathExtension:@"zip"]];
            if([zipOperation.zipData writeToFile:file atomically:YES] == NO)
                return nil;
            
            dataToSign = [[[NSData alloc] initWithContentsOfFile:file] autorelease];
        } else {
            dataToSign = [[[NSData alloc] initWithContentsOfFile:file] autorelease];
        }

        NSData* signData = [ctx processData:dataToSign withEncryptSignMode:GPGDetachedSign recipients:nil hiddenRecipients:nil];

        if (ctx.error) 
			@throw ctx.error;

        NSString* sigFile = [file stringByAppendingPathExtension:@"sig"];
        sigFile = [self normalizedAndUniquifiedPathFromPath:sigFile];
        [signData writeToFile:sigFile atomically:YES];
        
        return sigFile;
    } @catch (GPGException* e) {
        if([GrowlApplicationBridge isGrowlRunning]) {//This is in a loop, so only display Growl...
            NSString *msg = [NSString stringWithFormat:@"%@\n\n%@", [file lastPathComponent], e];
            [self displayOperationFailedNotificationWithTitle:[e reason] message:msg];
        }
    } @catch (NSException* e) {
        if([GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
            [self displayOperationFailedNotificationWithTitle:@"Signing failed."
                                                      message:[file lastPathComponent]];  // no e.reason?
    }

    return nil;
}

- (void)signFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(signFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = ([files count] == 1 
                                ? [NSString stringWithFormat:@"Signing %@", [self quoteOneFilesName:files]]
                                : [NSString stringWithFormat:@"Signing %i files", [files count]]);
    
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

    long double megabytes = [[self sizeOfFiles:files] unsignedLongLongValue] / kBytesInMB;
    
    if(megabytes > SIZE_WARNING_LEVEL_IN_MB) {
        int ret = [[NSAlert alertWithMessageText:@"Large File(s)"
                                   defaultButton:@"Continue"
                                 alternateButton:@"Cancel"
                                     otherButton:nil
                       informativeTextWithFormat:@"Encryption may take a longer time.\nPress 'Cancel' to abort."] 
                   runModalOnMain];
        
        if(ret == NSAlertAlternateReturn)
            return;
    }

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
    
    unsigned int signedFilesCount = 0;
    if(chosenKey != nil) {
        for(NSString* file in files) {
            // check before starting an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            NSString* sigFile = [self detachedSignFile:file withKeys:[NSArray arrayWithObject:chosenKey]];

            // check after an operation
            if (wrappedArgs.worker.amCanceling)
                return;

            if(sigFile != nil)
                signedFilesCount++;
        }
        
        if(signedFilesCount > 0) {
            [self displayOperationFinishedNotificationWithTitle:@"Signing finished"
                                                        message:[NSString 
                                                                 stringWithFormat:@"Finished signing %i file(s)", files.count]];
        }
    }
}

- (void)encryptFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(encryptFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = ([files count] == 1 
                                ? [NSString stringWithFormat:@"Encrypting %@", [self quoteOneFilesName:files]]
                                : [NSString stringWithFormat:@"Encrypting %i files", [files count]]);
    
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

    GPGDebugLog(@"encrypting file(s): %@...", [files componentsJoinedByString:@","]);
    
    if(files.count == 0)
        return;
    
    BOOL useASCII = [[[GPGOptions sharedOptions] valueForKey:@"UseASCIIOutput"] boolValue];
    GPGDebugLog(@"Output as ASCII: %@", useASCII ? @"YES" : @"NO");
    NSString *fileExtension = useASCII ? @"asc" : @"gpg";
    RecipientWindowController* rcp = [[[RecipientWindowController alloc] init] autorelease];
	int ret = [rcp runModal]; // thread-safe
	if(ret != 0)
		return;  // User pressed 'cancel'

    GPGEncryptSignMode mode = rcp.sign ? GPGEncryptSign : GPGPublicKeyEncrypt;
    NSArray* validRecipients = rcp.selectedKeys;
    GPGKey* privateKey = rcp.selectedPrivateKey;
    
    if(rcp.encryptForOwnKeyToo && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption canceled." 
                                                  message:@"No private key selected to add to recipients"];
        return;
    }
    if(rcp.sign && !privateKey) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption canceled." 
                                                  message:@"No private key selected for signing"];
        return;
    }
    
    if(rcp.encryptForOwnKeyToo && privateKey) {
        validRecipients = [[[NSSet setWithArray:validRecipients] 
                            setByAddingObject:[privateKey primaryKey]] 
                           allObjects];
    } else {
        validRecipients = [[NSSet setWithArray:validRecipients] allObjects];
    }

    // check before starting an operation
    if (wrappedArgs.worker.amCanceling)
        return;

    long double megabytes = 0;
    NSString* destination = nil;
    
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    typedef NSData*(^DataProvider)();
    DataProvider dataProvider = nil;
    
    if(files.count == 1) {
        NSString* file = [files objectAtIndex:0];
        BOOL isDirectory = YES;
        
        if (! [fmgr fileExistsAtPath:file isDirectory:&isDirectory]) {    
            [self displayOperationFailedNotificationWithTitle:@"File doesn't exist"
                                                      message:@"Please try again"];
            return;
        }
        if(isDirectory) {
            NSString* filename = [NSString stringWithFormat:@"%@.zip.gpg", [file lastPathComponent]];
            megabytes = [[self folderSize:file] unsignedLongLongValue] / kBytesInMB;
            destination = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
            dataProvider = ^{
                ZipOperation* operation = [[[ZipOperation alloc] init] autorelease];
                operation.filePath = file;
                operation.delegate = self;
                [operation start];
                
                return operation.zipData;
            };
        } else {
            NSNumber* fileSize = [self sizeOfFiles:[NSArray arrayWithObject:file]];
            megabytes = [fileSize unsignedLongLongValue] / kBytesInMB;
            destination = [file stringByAppendingFormat:@".%@", fileExtension];
            dataProvider = ^{
                return (NSData*)[NSData dataWithContentsOfFile:file];
            };
        }  
    } else if(files.count > 1) {
        megabytes = [[self sizeOfFiles:files] unsignedLongLongValue] / kBytesInMB;
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
    
    GPGDebugLog(@"destination: %@", destination);
    GPGDebugLog(@"fileSize: %@Mb", [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithDouble:megabytes]
                                                              numberStyle:NSNumberFormatterDecimalStyle]);        
    
    if(megabytes > SIZE_WARNING_LEVEL_IN_MB) {
        int ret = [[NSAlert alertWithMessageText:@"Large File(s)"
                                   defaultButton:@"Continue"
                                 alternateButton:@"Cancel"
                                     otherButton:nil
                       informativeTextWithFormat:@"Encryption may take a longer time.\nPress 'Cancel' to abort."] 
                   runModalOnMain];
        
        if(ret == NSAlertAlternateReturn)
            return;
    }
    
    NSAssert(dataProvider != nil, @"dataProvider can't be nil");
    NSAssert(destination != nil, @"destination can't be nil");
    
    // check before starting an operation
    if (wrappedArgs.worker.amCanceling)
        return;

    GPGController* ctx = [GPGController gpgController];
    // Only use armor for single files. otherwise it doesn't make much sense.
    ctx.useArmor = useASCII && [destination rangeOfString:@".asc"].location != NSNotFound;
    NSData* gpgData = nil;
    if(dataProvider != nil)
        gpgData = [[[NSData alloc] initWithData:dataProvider()] autorelease];

    NSData* encrypted = nil;
    if(mode == GPGEncryptSign && privateKey != nil)
        [ctx addSignerKey:[privateKey description]];
    @try{
        encrypted = [ctx processData:gpgData 
                          withEncryptSignMode:mode
                                   recipients:validRecipients
                             hiddenRecipients:nil];

        // check after a lengthy operation
        if (wrappedArgs.worker.amCanceling)
            return;
        
        if (ctx.error) 
			@throw ctx.error;
        
    } @catch(GPGException* localException) {
        [self displayOperationFailedNotificationWithTitle:[localException reason]  
                                                  message:[localException description]];
        return;
    } @catch(NSException* localException) {
        [self displayOperationFailedNotificationWithTitle:@"Encryption failed."  
                        message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
        return;
    }

    if(encrypted == nil) {
        // We should probably show the file from the exception too.
        [self displayOperationFailedNotificationWithTitle:@"Encryption failed."
                        message:[destination lastPathComponent]];
        return;
    }
    [encrypted writeToFile:destination atomically:YES];
    [self displayOperationFinishedNotificationWithTitle:@"Encryption finished." message:[destination lastPathComponent]];
}

- (void)decryptFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(decryptFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = ([files count] == 1 
                                ? [NSString stringWithFormat:@"Decrypting %@", [self quoteOneFilesName:files]]
                                : [NSString stringWithFormat:@"Decrypting %i files", [files count]]);
    
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

    GPGController* ctx = [GPGController gpgController];
    // [ctx setPassphraseDelegate:self];
    
    NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
    
    unsigned int decryptedFilesCount = 0;
    NSUInteger errorCount = 0;
    NSMutableString *errorMsgs = [NSMutableString string];

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
                NSData* inputData = [[[NSData alloc] initWithContentsOfFile:file] autorelease];
                GPGDebugLog(@"inputData.size: %lu", [inputData length]);
                
                NSData* outputData = [ctx decryptData:inputData];

                // check again after a potentially long operation
                if (wrappedArgs.worker.amCanceling)
                    return;
                
                if (outputData && [outputData length]) {
                    NSString* outputFile = [self normalizedAndUniquifiedPathFromPath:[file stringByDeletingPathExtension]];
                    NSError* error = nil;
                    [outputData writeToFile:outputFile options:NSDataWritingAtomic error:&error];
                    if(error != nil) 
                        NSLog(@"error while writing to output: %@", error);
                    else
                        decryptedFilesCount++;
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
                                                 @"No signatures found", @"verificationResult",
                                                 nil]];
                
                }
            }
        } @catch(NSException* ex) {
            ++errorCount;
            NSString *title, *msg;
            if ([ex isKindOfClass:[GPGException class]]) {
                title = [ex reason];
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
            }
            else {
                title = @"Decryption error";
                msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], 
                       @"An unexpected error occurred while decrypting."];
                NSLog(@"decryptData ex: %@", ex);
            }
            
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) {//This is in a loop, so only display Growl...
                [self displayOperationFailedNotificationWithTitle:title message:msg];
            }
            else {
                if ([errorMsgs length] > 0)
                    [errorMsgs appendString:@"\n"];
                [errorMsgs appendString:msg];
            }
        } 
    }
    
    dummyController.isActive = NO;
    
    if(decryptedFilesCount > 0 || errorCount > 0) {
        NSMutableString *summary = [NSMutableString string];
        if (decryptedFilesCount > 0 || errorCount < 1) {
            [summary appendFormat:@"Decrypted %i file(s).", decryptedFilesCount];
        }
        if (errorCount > 0) {
            if ([summary length] > 0)
                [summary appendString:@"\n"];
            [summary appendFormat:@"Problems with %i file(s).", errorCount];
            if ([errorMsgs length] > 0) {
                [summary appendString:@"\n\n"];
                [summary appendString:errorMsgs];
            }
        }
        
        [self displayOperationFinishedNotificationWithTitle:@"Decryption finished." message:summary];
    }

    [dummyController runModal]; // thread-safe
    [dummyController release];
}
 
- (void)verifyFiles:(NSArray *)files
{
    ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(verifyFilesSync:)];
    worker.delegate = self;
    worker.workerDescription = ([files count] == 1 
                                ? [NSString stringWithFormat:@"Verifying signature of %@", [self quoteOneFilesName:files]]
                                : [NSString stringWithFormat:@"Verifying signatures of %i files", [files count]]);
    
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
        NSString* signatureFile = serviceFile;
        NSString* signedFile = [FileVerificationController searchFileForSignatureFile:signatureFile];
        if(signedFile == nil) {
            NSString* tmp = [FileVerificationController searchSignatureFileForFile:signatureFile];
            signedFile = signatureFile;
            signatureFile = tmp;
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
                NSData* signatureFileData = [[[NSData alloc] initWithContentsOfFile:signatureFile] autorelease];
                NSData* signedFileData = [[[NSData alloc] initWithContentsOfFile:signedFile] autorelease];
                sigs = [ctx verifySignature:signatureFileData originalData:signedFileData];
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
                NSData* signedFileData = [[[NSData alloc] initWithContentsOfFile:serviceFile] autorelease];
                sigs = [ctx verifySignedData:signedFileData];

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
                verificationResult = @"Verification FAILED: No signatures found";
                
                NSColor* bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                
                NSRange range = [verificationResult rangeOfString:@"FAILED"];
                verificationResult = [[NSMutableAttributedString alloc] 
                                      initWithString:verificationResult];
                
                [verificationResult addAttribute:NSFontAttributeName 
                                           value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                                           range:range];
                [verificationResult addAttribute:NSBackgroundColorAttributeName 
                                           value:bgColor
                                           range:range];
                
                NSDictionary* result = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [signedFile lastPathComponent], @"filename",
                                        verificationResult, @"verificationResult", 
                                        nil];
                [fvc addResults:result];
            } else if(sigs.count > 0) {
                for(GPGSignature* sig in sigs) {
                    [fvc addResultFromSig:sig forFile:signedFile];
                }
            }
        } else {
            [fvc addResults:[NSDictionary dictionaryWithObjectsAndKeys:
                             [signedFile lastPathComponent], @"filename",
                             @"No verifiable data found", @"verificationResult",
                             nil]];
        }
    }

    [fvc runModal]; // thread-safe
}

- (void)growlVerificationResultsFor:(NSString *)file signatures:(NSArray *)signatures 
{
    if ([GrowlApplicationBridge isGrowlRunning] != YES)
        return;

    NSString *title = [NSString stringWithFormat:@"Verification for %@", 
                       [self quoteOneFilesName:[NSArray arrayWithObject:file]]];
    
    NSMutableString *summary = [NSMutableString string];
    if ([signatures count] > 0) {
        for (GPGSignature *gpgSig in signatures) {
            [summary appendFormat:@"%@\n", [gpgSig humanReadableDescription]];
        }
    }
    else {
        [summary appendString:@"No signatures found"];
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
    
    [[NSAlert alertWithMessageText:@"Import result:"
                     defaultButton:@"Ok"
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
    worker.workerDescription = ([files count] == 1 
                                ? [NSString stringWithFormat:@"Importing %@", [self quoteOneFilesName:files]]
                                : [NSString stringWithFormat:@"Importing of %i files", [files count]]);
    
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

	GPGController* gpgc = [GPGController gpgController];

    // gpgc.userInfo = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:1 /* ShowResultAction */], @"action", nil];

    NSUInteger foundKeysCount = 0; //Track valid key-files
    NSUInteger importedKeyCount = 0;
    NSUInteger importedSecretKeyCount = 0;
    NSUInteger newRevocationCount = 0;
    
    for(NSString* file in files) {
        // check before starting an operation
        if (wrappedArgs.worker.amCanceling)
            return;

        if([[self isDirectoryPredicate] evaluateWithObject:file] == YES) {
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) //This is in a loop, so only display Growl...
                [self displayOperationFailedNotificationWithTitle:@"Can't import keys from directory"
                                                          message:[file lastPathComponent]];
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

            /* 
            NSDictionary* importResults
            NSDictionary* changedKeys = [importResults valueForKey:GPGChangesKey];
            if(changedKeys.count > 0) {
                ++foundKeysCount;
                
                importedKeyCount += [[importResults valueForKey:@"importedKeyCount"] unsignedIntValue];
                importedSecretKeyCount += [[importResults valueForKey:@"importedSecretKeyCount"] unsignedIntValue];
                newRevocationCount += [[importResults valueForKey:@"newRevocationCount"] unsignedIntValue];
            } else if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) { //This is in a loop, so only display Growl... 
                [self displayOperationFailedNotificationWithTitle:@"No importable Keys found"
                                                          message:[file lastPathComponent]];
            }
             */
        } @catch(GPGException* ex) {
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) {//This is in a loop, so only display Growl...
                NSString *msg = [NSString stringWithFormat:@"%@\n\n%@", [file lastPathComponent], ex];
                [self displayOperationFailedNotificationWithTitle:[ex reason] message:msg];
            }
        } @catch(NSException* ex) {
            if(files.count == 1 || [GrowlApplicationBridge isGrowlRunning]) {//This is in a loop, so only display Growl...
                NSString *msg = [NSString stringWithFormat:@"%@\n\n%@", [file lastPathComponent], ex];
                [self displayOperationFailedNotificationWithTitle:@"Import failed." 
                                                          message:msg];
            }
        }
    }

#warning TODO - get informative counts from GPGController to reactivate import results alert.
    //Don't show result window when there were no imported keys
    if(foundKeysCount > 0) {
        [[NSAlert alertWithMessageText:@"Import result:"
                         defaultButton:@"Ok"
                       alternateButton:nil
                           otherButton:nil
             informativeTextWithFormat:@"%i key(s), %i secret key(s), %i revocation(s) ",
          importedKeyCount,
          importedSecretKeyCount,
          newRevocationCount]
         runModal];     
    }
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
        
        if([pbtype isEqualToString:NSPasteboardTypeString])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error=[NSString stringWithFormat:@"Error: Could not perform GPG operation. Pasteboard could not supply text string."];
				[self exitServiceRequest];
				return;
			}
		}
		else if([pbtype isEqualToString:NSPasteboardTypeRTF])
		{
			if(!(pboardString = [pboard stringForType:NSPasteboardTypeString]))
			{
				*error=[NSString stringWithFormat:@"Error: Could not perform GPG operation. Pasteboard could not supply text string."];
				[self exitServiceRequest];
				return;
			}
		}
		else
		{
			*error = NSLocalizedString(@"Error: Could not perform GPG operation.", @"Pasteboard could not supply the string in an acceptible format.");
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
    
	if(newString!=nil)
	{
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
    
	[self exitServiceRequest];
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
    savePanel.title = @"Choose Destination";
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
                     defaultButton:@"Ok"
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
    
    [[NSAlert alertWithMessageText:@"Verification successful."
                     defaultButton:@"Ok"
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:@"Good signature (%@ trust):\n\"%@\"",validity,userID]
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
	currentTerminateTimer=[NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(selfQuit:) userInfo:nil repeats:YES];
}

-(void)selfQuit:(NSTimer *)timer
{
    if ([_inProgressCtlr.serviceWorkerArray count] < 1) {
        [self cancelTerminateTimer];
        [NSApp terminate:self];
    }
}

@end
