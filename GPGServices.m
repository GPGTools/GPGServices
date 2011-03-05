//
//  GPGServices.m
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "GPGServices.h"

@implementation GPGServices

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[NSApp setServicesProvider:self];
//	NSUpdateDynamicServices();
	currentTerminateTimer=nil;
}


//
// Actual GPG Routines
//

-(void)importKey:(NSString *)inputString
{
	GPGData *inputData;
	NSDictionary *importedKeys;
	GPGContext *aContext = [[GPGContext alloc] init];

	inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

	NS_DURING
		importedKeys=[aContext importKeyData:inputData];
	NS_HANDLER
		[self displayMessageWindowWithTitleText:@"Import result:" bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
		[inputData release];
		[aContext release];
		return;
	NS_ENDHANDLER

	//if(([[importedKeys valueForKey:@"importedKeyCount"] intValue]+[[importedKeys valueForKey:@"importedSecretKeyCount"] intValue]+[[importedKeys valueForKey:@"newRevocationCount"] intValue])>0)
	[self displayMessageWindowWithTitleText:@"Import result:" bodyText:[NSString stringWithFormat:@"%i key(s), %i secret key(s), %i revocation(s) ",[[importedKeys valueForKey:@"importedKeyCount"] intValue],[[importedKeys valueForKey:@"importedSecretKeyCount"] intValue],[[importedKeys valueForKey:@"newRevocationCount"] intValue]]];
	[inputData release];
	[aContext release];
}

-(NSString *)myFingerprint
{
	NSString *result=nil;
	GPGKey *myKey;

	GPGOptions *myOptions=[[GPGOptions alloc] init];
	NSString *keyID=[myOptions optionValueForName:@"default-key"];
	[myOptions release];

	if(keyID==nil)
	{
		[self displayMessageWindowWithTitleText:@"Default key not set." bodyText:@"No default key is specified in the GPG Preferences."];
		return nil;
	}

	GPGContext *aContext = [[GPGContext alloc] init];

	NS_DURING
		myKey=[aContext keyFromFingerprint:keyID secretKey:NO];
		if(myKey==nil)
		{
			[self displayMessageWindowWithTitleText:@"Found no fingerprint." bodyText:@"Could not retrieve your key from keychain (maybe you've not set a default key in ~/.gnupg/gpg.conf)"];
			[aContext release];
			return nil;
		}
	NS_HANDLER
		result=nil;
		[self displayMessageWindowWithTitleText:@"Retrieving fingerprint failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
		[aContext release];
		return nil;
	NS_ENDHANDLER

	result=[[myKey formattedFingerprint] copy];
	[aContext release];
	return [result autorelease];
}




-(NSString *)myKey
{
	NSString *result=nil;
	GPGKey *myKey;
	NSData *keyData;
	GPGOptions *myOptions=[[GPGOptions alloc] init];
	NSString *keyID=[myOptions optionValueForName:@"default-key"];
	[myOptions release];
	if(keyID==nil)
	{
		[self displayMessageWindowWithTitleText:@"Default key not set." bodyText:@"No default key is specified in the GPG Preferences."];
		return nil;
	}

	GPGContext *aContext = [[GPGContext alloc] init];
	[aContext setUsesArmor:YES];
	[aContext setUsesTextMode:YES];

	NS_DURING
		myKey=[aContext keyFromFingerprint:keyID secretKey:NO];
		if(myKey==nil)
		{
			[self displayMessageWindowWithTitleText:@"Found no key." bodyText:@"Could not retrieve your key from keychain (maybe you've not set a default key in ~/.gnupg/gpg.conf)"];
			[aContext release];
			return nil;
		}
		keyData=[[aContext exportedKeys:[NSArray arrayWithObject:myKey]] data];
		if(keyData==nil)
		{
			[self displayMessageWindowWithTitleText:@"Exporting key failed." bodyText:@"Could not export key"];
			[aContext release];
			return nil;
		}
	NS_HANDLER
		result=nil;
		[self displayMessageWindowWithTitleText:@"Exporting key failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
		[aContext release];
		return nil;
	NS_ENDHANDLER

	[aContext release];
	result=[[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
	return [result autorelease];
}

-(NSString *)encryptTextString:(NSString *)inputString
{
	GPGData *inputData, *outputData;
	GPGContext *aContext = [[GPGContext alloc] init];
	NSMutableArray *recipients = [[NSMutableArray alloc] init];
	BOOL trustsAllKeys = NO;
	
	NSString* testPattern = @"moritz";
	
	[aContext setUsesArmor:YES];
	
	[recipients addObjectsFromArray:[[aContext keyEnumeratorForSearchPattern:pattern secretKeysOnly:NO] allObjects]];
	
	
	//for(GPGKey* k in recipients)
	//	NSLog(@"%@", [k email]);
	//NSLog(@"recipients: %@", recipients);

	//todo: just ask the user for recipients and whether we should sign the text
	//[self displayMessageWindowWithTitleText:@"BLABLABLA Encryption not implemented" bodyText:@"Please implement this funcionality if you're an developer."];
	//[NSApp runModalForWindow:recipientWindow];
	//[recipientWindow close];

	inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

	NS_DURING
		outputData=[aContext encryptedData:inputData withKeys:recipients trustAllKeys:trustsAllKeys];
	NS_HANDLER
		outputData = nil;
		switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		{
			case GPGErrorNoData:
				[self displayMessageWindowWithTitleText:@"Encryption failed." bodyText:@"No encryptable text was found within the selection."];
				break;
			case GPGErrorCancelled:
				[self displayMessageWindowWithTitleText:@"Encryption cancelled." bodyText:@"Encryption was cancelled."];
				break;
			default:
				[self displayMessageWindowWithTitleText:@"Encryption failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
				for(GPGKey* key in [[aContext operationResults] objectForKey:@"keyErrors"])
					NSLog(@"key: %@, error: %@", [key email], GPGErrorDescription([[[aContext operationResults] objectForKey:key] intValue]));
		}
		[inputData release];
		[aContext release];
		return nil;
	NS_ENDHANDLER
	
	[inputData release];
	[recipients release];
	[aContext release];

	return [[[NSString alloc] initWithData:[outputData data] encoding:NSUTF8StringEncoding] autorelease];
}

-(NSString *)decryptTextString:(NSString *)inputString
{
	GPGData *inputData, *outputData;
	GPGContext *aContext = [[GPGContext alloc] init];

	[aContext setPassphraseDelegate:self];

	inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

	NS_DURING
		outputData=[aContext decryptedData:inputData];
	NS_HANDLER
		outputData = nil;
		switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		{
			case GPGErrorNoData:
				[self displayMessageWindowWithTitleText:@"Decryption failed." bodyText:@"No decryptable text was found within the selection."];
				break;
			case GPGErrorCancelled:
				break;
			default:
				[self displayMessageWindowWithTitleText:@"Decryption failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
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
	GPGData *inputData, *outputData;
	GPGContext *aContext = [[GPGContext alloc] init];

	[aContext setPassphraseDelegate:self];

	inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

	NS_DURING
		outputData=[aContext signedData:inputData signatureMode:GPGSignatureModeClear];
	NS_HANDLER
		outputData = nil;
		switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		{
			case GPGErrorNoData:
				[self displayMessageWindowWithTitleText:@"Signing failed." bodyText:@"No signable text was found within the selection."];
				break;
			case GPGErrorBadPassphrase:
				[self displayMessageWindowWithTitleText:@"Signing failed." bodyText:@"The passphrase is incorrect."];
				break;
			case GPGErrorUnusableSecretKey:
				[self displayMessageWindowWithTitleText:@"Signing failed." bodyText:@"The default secret key is unusable."];
				break;
			case GPGErrorCancelled:
				break;
			default:
				[self displayMessageWindowWithTitleText:@"Signing failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
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
	GPGData *inputData;
	NSArray *sigs;
	GPGSignature *sig;
	NSString *userID, *validity;
	GPGContext *aContext = [[GPGContext alloc] init];

	inputData=[[GPGData alloc] initWithDataNoCopy:[inputString dataUsingEncoding:NSUTF8StringEncoding]];

	NS_DURING
		sigs=[aContext verifySignedData:inputData originalData:nil];
	NS_HANDLER
		sigs=nil;
		if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
			[self displayMessageWindowWithTitleText:@"Verification failed." bodyText:@"No verifiable text was found within the selection"];
		else
			[self displayMessageWindowWithTitleText:@"Verification failed." bodyText:[NSString stringWithFormat:@"%@",GPGErrorDescription([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])]];
		[inputData release];
		[aContext release];
		return;
	NS_ENDHANDLER


		if([sigs count]>0)
		{
			sig=[sigs objectAtIndex:0];
			if(GPGErrorCodeFromError([sig status])==GPGErrorNoError)
			{
				userID=[[aContext keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
				validity=[sig validityDescription];
				[self displayMessageWindowWithTitleText:@"Verification successful." bodyText:[NSString stringWithFormat:@"Good signature (%@ trust):\n\"%@\"",validity,userID]];
			}
			else
				[self displayMessageWindowWithTitleText:@"Verification FAILED." bodyText:GPGErrorDescription([sig status])];
		}
		else
			[self displayMessageWindowWithTitleText:@"Verification error." bodyText:@"Unable to verify due to an internal error"];
	[inputData release];
	[aContext release];
}


//
//Services handling routines
//

-(void)dealWithPasteboard:(NSPasteboard *)pboard userData:(NSString *)userData mode:(ServiceModeEnum)mode error:(NSString **)error
{
	NSString *pboardString;
	NSString *newString=nil;
	NSString *type;

	[self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];

	if(mode!=MyKeyService && mode!=MyFingerprintService)
	{
		type = [pboard availableTypeFromArray:[NSArray arrayWithObjects:NSHTMLPboardType, NSStringPboardType, NSRTFPboardType, nil]];

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

//
//Gui routines
//

-(void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body
{
	[messageHeadingText setStringValue:title];
	[messageBodyText setStringValue:body];
	[NSApp runModalForWindow:messageWindow];
	[messageWindow close];
}

-(NSString *)context:(GPGContext *)context passphraseForKey:(GPGKey *)key again:(BOOL)again
{
	NSString *passphrase;
	int flag;
	[passphraseText setStringValue:@""];
	flag=[NSApp runModalForWindow:passphraseWindow];
	passphrase=[[[passphraseText stringValue] copy] autorelease];
	[passphraseWindow close];
	if(flag)
		return passphrase;
	else
		return nil;
}


-(IBAction)closeModalWindow:(id)sender
{[NSApp stopModalWithCode:[sender tag]];}



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
