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

@implementation GPGServices

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[NSApp setServicesProvider:self];
    //	NSUpdateDynamicServices();
	currentTerminateTimer=nil;
    
    [GrowlApplicationBridge setGrowlDelegate:self];
}


//
// Actual GPG Routines
//

-(void)importKey:(NSString *)inputString
{
	NSDictionary *importedKeys = nil;
	GPGContext *aContext = [[GPGContext alloc] init];
	GPGData* inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    
	NS_DURING
    importedKeys=[aContext importKeyData:inputData];
	NS_HANDLER
    [self displayMessageWindowWithTitleText:@"Import result:"
                                   bodyText:GPGErrorDescription([[[localException userInfo] 
                                                                  objectForKey:@"GPGErrorKey"] 
                                                                 intValue])];
    [inputData release];
    [aContext release];
    return;
	NS_ENDHANDLER
    [[NSAlert alertWithMessageText:@"Import result:"
                     defaultButton:@"Ok"
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:@"%i key(s), %i secret key(s), %i revocation(s) ",
      [[importedKeys valueForKey:@"importedKeyCount"] intValue],
      [[importedKeys valueForKey:@"importedSecretKeyCount"] intValue],
      [[importedKeys valueForKey:@"newRevocationCount"] intValue]]
     runModal];
	
	[inputData release];
	[aContext release];
}


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


-(NSSet*)myPrivateKeys {
    GPGContext* context = [[GPGContext alloc] init];
    NSSet* keySet = [NSSet setWithArray:[[context keyEnumeratorForSearchPattern:@"" secretKeysOnly:YES] allObjects]];
    [context release];
    
    return keySet;
}

- (GPGKey*)myPrivateKey {
    GPGOptions *myOptions=[[GPGOptions alloc] init];
	NSString *keyID=[myOptions optionValueForName:@"default-key"];
	[myOptions release];
	if(keyID == nil)
        return nil;
    
	GPGContext *aContext = [[GPGContext alloc] init];
    
	NS_DURING
    GPGKey* defaultKey=[aContext keyFromFingerprint:keyID secretKey:YES];
    [aContext release];
    return defaultKey;
    NS_HANDLER
	NS_ENDHANDLER
    
    [aContext release];
    return nil;
}

-(NSString *)myFingerprint
{
    GPGKey* chosenKey = [self myPrivateKey];
    
    NSSet* availableKeys = [self myPrivateKeys];
    if(chosenKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
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
    GPGKey* selectedPrivateKey = [self myPrivateKey];
    
    NSSet* availableKeys = [self myPrivateKeys];
    if(selectedPrivateKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
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
    NS_DURING
    keyData = [[ctx exportedKeys:[NSArray arrayWithObject:selectedPrivateKey]] data];
    
    if(keyData == nil) {
        [[NSAlert alertWithMessageText:@"Exporting key failed." 
                        defaultButton:@"Ok"
                      alternateButton:nil
                          otherButton:nil
            informativeTextWithFormat:@"Could not export key %@", [selectedPrivateKey shortKeyID]] 
         runModal];
        
        [ctx release];
        return nil;
    }
	NS_HANDLER
    GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
    [self displayMessageWindowWithTitleText:@"Exporting key failed."
                                   bodyText:GPGErrorDescription(error)];
    [ctx release];
    return nil;
	NS_ENDHANDLER
    
	[ctx release];
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
        
        if(validRecipients.count == 0) {
            [self displayMessageWindowWithTitleText:@"Encryption failed."
                                           bodyText:@"No valid recipients found"];

            [inputData release];
            [aContext release];
            
            return nil;
        }
        
		NS_DURING
		if(sign)
			outputData=[aContext encryptedSignedData:inputData withKeys:validRecipients trustAllKeys:trustsAllKeys];
		else
			outputData=[aContext encryptedData:inputData withKeys:validRecipients trustAllKeys:trustsAllKeys];
		NS_HANDLER
		outputData = nil;
		switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		{
			case GPGErrorNoData:
                [self displayMessageWindowWithTitleText:@"Encryption failed."  
                                               bodyText:@"No encryptable text was found within the selection."];
                break;
			case GPGErrorCancelled:
				break;
			default: {
                GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
                [self displayMessageWindowWithTitleText:@"Encryption failed."  
                                               bodyText:GPGErrorDescription(error)];
            }
		}
		[inputData release];
		[aContext release];
		
		return nil;
		NS_ENDHANDLER
	}
	
	[aContext release];
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}

-(NSString *)decryptTextString:(NSString *)inputString
{
    GPGData *outputData = nil;
	GPGContext *aContext = [[GPGContext alloc] init];
    
	[aContext setPassphraseDelegate:self];
    
	GPGData *inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    
	NS_DURING
    outputData=[aContext decryptedData:inputData];
	NS_HANDLER
    outputData = nil;
    switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
    {
        case GPGErrorNoData:
            [self displayMessageWindowWithTitleText:@"Decryption failed."
                                           bodyText:@"No decryptable text was found within the selection."];
            break;
        case GPGErrorCancelled:
            break;
        default: {
            GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
            [self displayMessageWindowWithTitleText:@"Decryption failed." 
                                           bodyText:GPGErrorDescription(error)];
        }
    }
    [inputData release];
    [aContext release];
    return nil;
	NS_ENDHANDLER
	[inputData release];
	[aContext release];
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}


-(NSString *)signTextString:(NSString *)inputString
{
	GPGContext *aContext = [[GPGContext alloc] init];
	[aContext setPassphraseDelegate:self];
    
	GPGData *inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    GPGKey* chosenKey = [self myPrivateKey];
    
    NSSet* availableKeys = [self myPrivateKeys];
    if(chosenKey == nil || availableKeys.count > 1) {
        KeyChooserWindowController* wc = [[KeyChooserWindowController alloc] init];
        if([wc runModal] == 0) 
            chosenKey = wc.selectedKey;
        else
            chosenKey = nil;
        
        [wc release];
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
	NS_DURING
    outputData=[aContext signedData:inputData signatureMode:GPGSignatureModeClear];
	NS_HANDLER
    outputData = nil;
    switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
    {
        case GPGErrorNoData:
            [self displayMessageWindowWithTitleText:@"Signing failed."
                                           bodyText:@"No signable text was found within the selection."];
            break;
        case GPGErrorBadPassphrase:
            [self displayMessageWindowWithTitleText:@"Signing failed."
                                           bodyText:@"The passphrase is incorrect."];
            break;
        case GPGErrorUnusableSecretKey:
            [self displayMessageWindowWithTitleText:@"Signing failed."
                                           bodyText:@"The default secret key is unusable."];
            break;
        case GPGErrorCancelled:
            break;
        default: {
            GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
            [self displayMessageWindowWithTitleText:@"Signing failed."
                                           bodyText:GPGErrorDescription(error)];
        }
    }
    [inputData release];
    [aContext release];
    return nil;
	NS_ENDHANDLER
	[inputData release];
	[aContext release];
    
	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}


-(void)verifyTextString:(NSString *)inputString
{
	GPGContext *aContext = [[GPGContext alloc] init];
    
	GPGData* inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSArray *sigs = nil;
	NS_DURING
    sigs=[aContext verifySignedData:inputData originalData:nil];
	NS_HANDLER
    sigs=nil;
    if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
        [self displayMessageWindowWithTitleText:@"Verification failed." 
                                       bodyText:@"No verifiable text was found within the selection"];
    else {
        GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
        [self displayMessageWindowWithTitleText:@"Verification failed." 
                                       bodyText:GPGErrorDescription(error)];
    }
    [inputData release];
    [aContext release];
    return;
	NS_ENDHANDLER
    
    
    if([sigs count]>0)
    {
        GPGSignature* sig=[sigs objectAtIndex:0];
        if(GPGErrorCodeFromError([sig status])==GPGErrorNoError)
        {
            NSString* userID=[[aContext keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
            NSString* validity=[sig validityDescription];
            
            [[NSAlert alertWithMessageText:@"Verification successful."
                             defaultButton:@"Ok"
                           alternateButton:nil
                               otherButton:nil
                 informativeTextWithFormat:@"Good signature (%@ trust):\n\"%@\"",validity,userID]
             runModal];
        }
        else {
            [self displayMessageWindowWithTitleText:@"Verification FAILED."
                                           bodyText:GPGErrorDescription([sig status])];
        }
    }
    else
        [self displayMessageWindowWithTitleText:@"Verification error."
                                       bodyText:@"Unable to verify due to an internal error"];

	[inputData release];
	[aContext release];
}

- (void)encryptFiles:(NSArray*)files {
    BOOL trustAllKeys = YES;
    
    NSLog(@"encrypting files: %@...", [files componentsJoinedByString:@","]);
    
    if(files.count == 0)
        return;
    else if(files.count > 1) 
        [self displayMessageWindowWithTitleText:@"Verification error."
                                       bodyText:@"Only one file at a time please."];

    RecipientWindowController* rcp = [[RecipientWindowController alloc] init];
	int ret = [rcp runModal];
    [rcp release];
	if(ret != 0) {
        //User pressed 'cancel'
		return;
	} else {
    	BOOL sign = rcp.sign;
        NSArray* validRecipients = rcp.selectedKeys;
        
        NSFileManager* fmgr = [[[NSFileManager alloc] init] autorelease];
        for(NSString* file in files) {
            BOOL isDirectory = YES;
            [fmgr fileExistsAtPath:file isDirectory:&isDirectory];
            if(isDirectory == YES) {
                [self displayMessageWindowWithTitleText:@"File is a directory"
                                               bodyText:@"Encryption of directories isn't supported"];
                return;
            }
            
            NSError* error = nil;
            NSNumber* fileSize = [[fmgr attributesOfItemAtPath:file error:&error] valueForKey:NSFileSize];
            double megabytes = [fileSize doubleValue] / 1048576;
            
            NSLog(@"fileSize: %@Mb", [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithDouble:megabytes]
                                                                    numberStyle:NSNumberFormatterDecimalStyle]);
            if(megabytes > 10) {
                int ret = [[NSAlert alertWithMessageText:@"Large File"
                                          defaultButton:@"Continue"
                                        alternateButton:@"Cancel"
                                            otherButton:nil
                               informativeTextWithFormat:@"Encryption will take a long time.\nPress 'Cancel' to abort."] 
                           runModal];
                
                if(ret == NSAlertAlternateReturn)
                    return;
            }
            
            NSURL* destination = [self getFilenameForSavingWithSuggestedPath:file
                                                      withSuggestedExtension:@".gpg"];
            if(destination == nil)
                return;
            
            /*
             NSError* error = nil;
             NSData* data = [NSData dataWithContentsOfFile:file
             options:NSDataReadingMapped 
             error:&error];
             if(error)
             [self displayMessageWindowWithTitleText:@"Error while reading contents of file"
             bodyText:[error description]];
             */
            
            if(megabytes > 10) {
                [GrowlApplicationBridge notifyWithTitle:@"Encrypting..."
                                            description:[file lastPathComponent]
                                       notificationName:@"EncryptionStarted"
                                               iconData:[NSData data]
                                               priority:0
                                               isSticky:NO
                                           clickContext:file];
            }
            
            GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
            GPGData* gpgData = [[[GPGData alloc] initWithContentsOfFile:file] autorelease];
            GPGData* encrypted = nil;
            
            if(sign == NO)
                encrypted = [ctx encryptedData:gpgData 
                                      withKeys:validRecipients
                                  trustAllKeys:trustAllKeys];
            else
                encrypted = [ctx encryptedSignedData:gpgData
                                            withKeys:validRecipients
                                        trustAllKeys:trustAllKeys];
            
            [encrypted.data writeToURL:destination atomically:YES];
            
            [GrowlApplicationBridge notifyWithTitle:@"Encryption finished"
                                        description:[destination lastPathComponent]
                                   notificationName:@"EncryptionSucceeded"
                                           iconData:[NSData data]
                                           priority:0
                                           isSticky:NO
                                       clickContext:destination];
        }
    }
}

//
//Services handling routines
//

-(void)dealWithPasteboard:(NSPasteboard *)pboard userData:(NSString *)userData mode:(ServiceModeEnum)mode error:(NSString **)error
{
	[self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
    
    NSString *pboardString = nil;
	if(mode!=MyKeyService && mode!=MyFingerprintService)
	{
		NSString* type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:
                                                         NSHTMLPboardType, 
                                                         NSStringPboardType, 
                                                         NSRTFPboardType,
                                                         NSFilenamesPboardType, 
                                                         nil]];
        
		if([type isEqualToString:NSHTMLPboardType])
		{
			if(!(pboardString = [pboard stringForType:NSHTMLPboardType]))
			{
				*error=[NSString stringWithFormat:@"Error: Could not perform GPG operation. Pasteboard could not supply HTML string."];
				[self exitServiceRequest];
				return;
			}
		}
		else if([type isEqualToString:NSStringPboardType])
		{
			if(!(pboardString = [pboard stringForType:NSStringPboardType]))
			{
				*error=[NSString stringWithFormat:@"Error: Could not perform GPG operation. Pasteboard could not supply text string."];
				[self exitServiceRequest];
				return;
			}
		}
		else if([type isEqualToString:NSRTFPboardType])
		{
			if(!(pboardString = [pboard stringForType:NSStringPboardType]))
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
		[pboard declareTypes:[NSArray arrayWithObjects:NSStringPboardType,NSHTMLPboardType,nil] owner:nil];
		[pboard setString:newString forType:NSStringPboardType];
		[pboard setString:[NSString stringWithFormat:@"<pre>%@</pre>",newString] forType:NSHTMLPboardType];
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

-(void)encryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
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
        [self encryptFiles:filenames];
    }
    
    [pool release];
}

//
//Gui routines
//

-(void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body
{
    /*
	[messageHeadingText setStringValue:title];
	[messageBodyText setStringValue:body];
	[NSApp runModalForWindow:messageWindow];
	[messageWindow close];
     */
    
    [[NSAlert alertWithMessageText:title
                    defaultButton:@"Ok"
                  alternateButton:nil
                      otherButton:nil
         informativeTextWithFormat:[NSString stringWithFormat:@"%@", body]] runModal];
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
	[recipientWindow close];
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
