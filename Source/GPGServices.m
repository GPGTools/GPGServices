//
// GPGServices.m
// GPGServices
//
// Created by Robert Goldsmith on 24/06/2006.
// Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "GPGServices.h"
#import "GPGServices_Private.h"

static const float kBytesInMB = 1.e6; // Apple now uses this vs 2^20
static NSString *const tempTemplate = @"_gpg(XXX).tmp";
static NSUInteger const suffixLen = 5;

static NSString *const showInFinderActionIdentifier = @"SHOW_IN_FINDER_ACTION";
static NSString *const fileCategoryIdentifier = @"FILE_CATEGORY";

static NSString *const ALL_VERIFICATION_RESULTS_KEY = @"verificationResults";
static NSString *const OPERATION_IDENTIFIER_KEY = @"operationIdentifier";
static NSString *const VERIFICATION_CONTROLLER_KEY = @"verificationController";
static NSString *const VERIFICATION_RESULT_KEY = @"verificationResult";


static NSString *const NOTIFICATION_TITLE_KEY = @"title";
static NSString *const NOTIFICATION_MESSAGE_KEY = @"message";
static NSString *const ALERT_TITLE_KEY = @"alertTitle";
static NSString *const ALERT_MESSAGE_KEY = @"alertMessage";



static NSString *const NotificationDismissalDelayKey = @"NotificationDismissalDelay";



@implementation GPGServices

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

	[NSApp setServicesProvider:self];
	currentTerminateTimer = nil;

	_inProgressCtlr = [[InProgressWindowController alloc] init];
	
	
	if (@available(macOS 10.14, *)) {
		UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
		center.delegate = self; // Without a working delegate, the notifications are only visible in the notification center and not on screen.

		UNNotificationAction* showInFinderAction = [UNNotificationAction
			  actionWithIdentifier:showInFinderActionIdentifier
			  title:localized(@"Show in Finder")
			  options:UNNotificationActionOptionNone];

		UNNotificationCategory *fileNotificationCategory = [UNNotificationCategory
			  categoryWithIdentifier:fileCategoryIdentifier
			  actions:@[showInFinderAction]
			  intentIdentifiers:@[]
			  options:UNNotificationCategoryOptionCustomDismissAction];

		[center setNotificationCategories:[NSSet setWithObjects:fileNotificationCategory, nil]];
		
		// Request authorization to show notifications.
		[center requestAuthorizationWithOptions:(UNAuthorizationOptionBadge | UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
							  completionHandler:^(BOOL granted, NSError * _Nullable error) {}];
		
		[center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
			self->_alertStyle = settings.alertStyle;
		}];
		
		UNNotificationResponse *response = aNotification.userInfo[NSApplicationLaunchUserNotificationKey];
		if (response && [response isKindOfClass:[UNNotificationResponse class]]) {
			[self performSelectorOnMainThread:@selector(handleNotificationResponseOnMain:)
			   withObject:response
			waitUntilDone:NO];
		}
	}
}
- (void)handleNotificationResponseOnMain:(UNNotificationResponse *)response __OSX_AVAILABLE(10.14) {
	[self userNotificationCenter:[UNUserNotificationCenter currentNotificationCenter]
  didReceiveNotificationResponse:response
		   withCompletionHandler:^{}];
}



- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
	[self cancelTerminateTimer];
	BOOL failed = NO;
	
	NSMutableArray *filesToImport = [NSMutableArray new];
	NSMutableArray *filesToVerify = [NSMutableArray new];
	NSMutableArray *filesToDecrypt = [NSMutableArray new];
	NSMutableArray *filesToEncrypt = [NSMutableArray new];
	
	for (NSString *path in filenames) {
		GPGFileStream *fileStream = [GPGFileStream fileStreamForReadingAtPath:path];
		if (!fileStream) {
			failed = YES;
			continue;
		}
		
		GPGStream *unArmoredStream;
		if (fileStream.isArmored) {
			GPGUnArmor *unArmor = [GPGUnArmor unArmorWithGPGStream:fileStream];
			NSData *unArmoredData;
			if (fileStream.length > 10 * 1024) {
				unArmoredData = [unArmor decodeHeader];
			} else {
				unArmoredData = [unArmor decodeAll];
			}
			unArmoredStream = [GPGMemoryStream memoryStreamForReading:unArmoredData];
		} else {
			unArmoredStream = fileStream;
		}
		
		GPGPacketParser *parser = [GPGPacketParser packetParserWithStream:unArmoredStream];
		GPGPacket *packet = [parser nextPacket];
        // Bug #257: If the first packet is not a known packet GPG Services
        //           starts encrypt operation.
        //
        // GPG Services only checks the first packet it finds for known packets.
        // If no match is found it's assumed that the file is not a OpenPGP related file
        // and thus the user wants to encrypt the file instead.
        //
        // In some cases however the first packet is a marker packet instead. In this case
        // GPG Services will skip that packet and check the next one.
        // TODO: Should maybe enhanced to loop through additional packets, if not too expensive.
        if(packet.tag == GPGMarkerPacketTag) {
            packet = [parser nextPacket];
        }
        
		BOOL verify = NO;
		BOOL import = NO;
		BOOL decrypt = NO;
		
		
		switch (packet.tag) {
			case GPGSignaturePacketTag: {
				GPGSignaturePacket *thePacket = (id)packet;
				if (thePacket.version < 2 || thePacket.version > 4) {
					break;
				}
				switch (thePacket.type) {
					case GPGBinarySignature:
					case GPGTextSignature:
						verify = YES;
						break;
					case GPGRevocationSignature:
					case GPGSubkeyRevocationSignature:
						import = YES;
						break;
					default:
						break;
				}
				break;
			}
			case GPGOnePassSignaturePacketTag: {
				GPGOnePassSignaturePacket *thePacket = (id)packet;
				if (thePacket.version != 3) {
					break;
				}
				if (thePacket.type != 0 && thePacket.type != 1) {
					break;
				}
				decrypt = YES;
				break;
			}
			case GPGPublicKeyEncryptedSessionKeyPacketTag: {
				GPGPublicKeyEncryptedSessionKeyPacket *thePacket = (id)packet;
				if (thePacket.version != 3) {
					break;
				}
				decrypt = YES;
				break;
			}
			case GPGSymmetricEncryptedSessionKeyPacketTag: {
				GPGSymmetricEncryptedSessionKeyPacket *thePacket = (id)packet;
				if (thePacket.version != 4) {
					break;
				}
				decrypt = YES;
				break;
			}
			default:
				break;
		}
		
		if (verify) {
			[filesToVerify addObject:path];
		} else if (import) {
			[filesToImport addObject:path];
		} else if (decrypt) {
			[filesToDecrypt addObject:path];
		} else {
			[filesToEncrypt addObject:path];
		}
	}
	
	BOOL havePGPFiles = NO;
	if (filesToVerify.count > 0) {
		havePGPFiles = YES;
		[self verifyFiles:filesToVerify];
	}
	if (filesToDecrypt.count > 0) {
		havePGPFiles = YES;
		[self decryptFiles:filesToDecrypt];
	}
	if (filesToImport.count > 0) {
		havePGPFiles = YES;
		[self importFiles:filesToImport];
	}
	if (filesToEncrypt.count > 0) {
		if (havePGPFiles) {
			// Do not allow encryption and another operation with the same file-set.
			failed = YES;
		} else {
			[self encryptFiles:filesToEncrypt];
		}
	}
	
	if (failed) {
		[NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
	} else {
		[NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
	}
	
	[self goneIn60Seconds];
}

#pragma mark -
#pragma mark GPG-Helper

// It appears all importKey.. functions were disabled over how libmacgpg handles importing,
// but apperently GPGAccess handles this identically.
- (void)importKeyFromData:(NSData *)data {
	GPGController *gpgc = [[GPGController alloc] init];

	NSString *importText = nil;

	@try {
		importText = [gpgc importFromData:data fullImport:NO];

		if (gpgc.error) {
			@throw gpgc.error;
		}
	} @catch (GPGException *ex) {
		[self displayOperationFailedNotificationWithTitle:[ex reason]
												  message:[ex description]];
		return;
	} @catch (NSException *ex) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Import failed")
												  message:[ex description]];
		return;
	}

	[self displayOperationFinishedNotificationWithTitle:localized(@"Import result")
												message:importText];
}

- (void)importKey:(NSString *)inputString {
	[self importKeyFromData:[inputString dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSSet *)myPrivateKeys {
	return [[GPGKeyManager sharedInstance].allKeys objectsPassingTest:^BOOL(GPGKey *key, BOOL *stop) {
		return key.secret;
	}];
}

+ (NSString *)myPrivateFingerprint {
	return [[GPGOptions sharedOptions] valueInGPGConfForKey:@"default-key"];
}

+ (GPGKey *)myPrivateKey {
	NSString *fingerprint = [GPGServices myPrivateFingerprint];

	if (fingerprint.length == 0) {
		return nil;
	}

	@try {
		for (GPGKey *key in self.myPrivateKeys) {
			if ([key.textForFilter rangeOfString:fingerprint].length > 0) {
				return key;
			}
		}		
	} @catch (NSException *e) {
	}
	return nil;
}

#pragma mark -
#pragma mark Validators

+ (KeyValidatorT)canEncryptValidator {
	KeyValidatorT block = ^(GPGKey *key) {
		if ([key canAnyEncrypt] && key.validity < GPGValidityInvalid) {
			return YES;
		}
		return NO;
	};

	return [block copy];
}

+ (KeyValidatorT)canSignValidator {
	KeyValidatorT block = ^(GPGKey *key) {
		if ([key canAnySign] && key.validity < GPGValidityInvalid) {
			return YES;
		}
		return NO;
	};

	return [block copy];
}

+ (KeyValidatorT)isActiveValidator {
	KeyValidatorT block = ^(GPGKey *key) {
		// Secret keys are never marked as revoked! Use public key
		key = [key primaryKey];

		if (![key expired] &&
			![key revoked] &&
			![key invalid] &&
			![key disabled]) {
			return YES;
		}

		for (GPGKey *aSubkey in [key subkeys]) {
			if (![aSubkey expired] &&
				![aSubkey revoked] &&
				![aSubkey invalid] &&
				![aSubkey disabled]) {
				return YES;
			}
		}
		return NO;
	};

	return [block copy];
}

#pragma mark -
#pragma mark Text Stuff

- (NSString *)myFingerprint {
	KeyChooserWindowController *wc = [[KeyChooserWindowController alloc] init];
	GPGKey *chosenKey = wc.selectedKey;

	if (chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
		if ([wc runModal] == 0) {
			chosenKey = wc.selectedKey;
		} else {
			chosenKey = nil;
		}
	}

	if (chosenKey != nil) {
		NSString *fp = [[chosenKey fingerprint] copy];
		NSMutableArray *arr = [NSMutableArray arrayWithCapacity:10];
		NSUInteger fpLength = [fp length];
		// expect 40-length string; breaking into 10 4-char chunks
		const int blkSize = 4;
		for (NSUInteger pos = 0; pos < fpLength; pos += blkSize) {
			NSUInteger nSize = MIN(fpLength - pos, blkSize);
			[arr addObject:[fp substringWithRange:NSMakeRange(pos, nSize)]];
		}
		return [arr componentsJoinedByString:@" "];
	}

	return nil;
}

- (NSString *)myKey {
	KeyChooserWindowController *wc = [[KeyChooserWindowController alloc] init];
	GPGKey *selectedPrivateKey = wc.selectedKey;

	if (selectedPrivateKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
		if ([wc runModal] == 0) {
			selectedPrivateKey = wc.selectedKey;
		} else {
			selectedPrivateKey = nil;
		}
	}

	if (selectedPrivateKey == nil) {
		return nil;
	}

	GPGController *ctx = [GPGController gpgController];
	ctx.useArmor = YES;

	@try {
		NSData *keyData = [ctx exportKeys:[NSArray arrayWithObject:selectedPrivateKey] allowSecret:NO fullExport:NO];

		if (keyData == nil) {
			
			NSString *msg = localizedWithFormat(@"Could not export key %@", selectedPrivateKey.keyID);
			[self displayOperationFailedNotificationWithTitle:localized(@"Export failed")
													  message:msg];
			return nil;
		} else {
			return [[NSString alloc] initWithData:keyData
										  encoding:NSUTF8StringEncoding];
		}
	} @catch (NSException *localException) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Export failed")
												  message:localException.reason];
	}

	return nil;
}

- (NSString *)encryptTextString:(NSString *)inputString {
	GPGController *ctx = [GPGController gpgController];

	ctx.trustAllKeys = YES;
	ctx.useArmor = YES;

	RecipientWindowController *rcp = [[RecipientWindowController alloc] init];
	NSInteger ret = [rcp runModal];

	if (ret != 0) {
		return nil;  // User pressed 'cancel'
	}
	NSData *inputData = [inputString UTF8Data];
	NSSet *validRecipients = rcp.selectedKeys;
	GPGKey *privateKey = rcp.selectedPrivateKey;

	if (rcp.encryptForOwnKeyToo) {
		validRecipients = [validRecipients setByAddingObject:privateKey];
	}

	GPGEncryptSignMode mode = (rcp.sign ? GPGSign : 0) | (validRecipients.count ? GPGPublicKeyEncrypt : 0) | (rcp.symetricEncryption ? GPGSymetricEncrypt : 0);


	@try {
		if (mode & GPGSign) {
			[ctx addSignerKey:[privateKey description]];
		}

		NSData *outputData = [ctx processData:inputData
							  withEncryptSignMode:mode
									   recipients:validRecipients
								 hiddenRecipients:nil];

		if (ctx.error) {
			if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
				return nil;
			}
			@throw ctx.error;
		}

		return [outputData gpgString];
	} @catch (GPGException *localException) {
		[self displayOperationFailedNotificationWithTitle:[localException reason]
												  message:[localException description]];
		return nil;
	} @catch (NSException *localException) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Encryption failed")
												  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
		/*
		 * switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		 * {
		 *  case GPGErrorNoData:
		 *      [self displayOperationFailedNotificationWithTitle:localized(@"Encryption failed")
		 *                                                message:localized(@"No encryptable text was found within the selection")];
		 *      break;
		 *  case GPGErrorCancelled:
		 *      break;
		 *  default: {
		 *      GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
		 *      [self displayOperationFailedNotificationWithTitle:localized(@"Encryption failed")
		 *                                                message:GPGErrorDescription(error)];
		 *  }
		 * }
		 */
		return nil;
	}


	return nil;
}

- (NSString *)decryptTextString:(NSString *)inputString {
	GPGController *ctx = [GPGController gpgController];

	ctx.userInfo = @{@"type": @"text"};
	ctx.delegate = self;
	ctx.useArmor = YES;

	NSData *outputData = nil;

	@try {
		outputData = [ctx decryptData:[inputString UTF8Data]];

		
		// Check for canceling because of the no-mdc warning.
		if ([ctx.userInfo[@"cancelled"] boolValue]) {
			return nil;
		}
		
		if (ctx.error) {
			if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
				return nil;
			}
			@throw ctx.error;
		}

		
		NSArray *sigs = ctx.signatures;
		if (sigs.count > 0) {
			GPGSignature *sig = [sigs objectAtIndex:0];
			NSDictionary *result = [self resultForSignature:sig file:nil];
			
			[self displayNotificationWithTitle:result[NOTIFICATION_TITLE_KEY]
									   message:result[NOTIFICATION_MESSAGE_KEY]
										 files:nil
									  userInfo:nil
										failed:NO];
		}

	} @catch (GPGException *ex) {
		
		NSString *title;
		NSString *message;
		
		switch (ex.errorCode) {
			case GPGErrorNoSecretKey: {
				NSMutableArray *missingSecKeys = [NSMutableArray new];
				NSArray *missingKeys = ex.gpgTask.statusDict[@"NO_SECKEY"]; //Array of Arrays of String!
				NSUInteger count = missingKeys.count;
				NSUInteger i = 0;
				for (; i < count; i++) {
					[missingSecKeys addObject:missingKeys[i][0]];
				}
				
				title = localizedWithFormat(@"NO_SEC_KEY_DECRYPT_TEXT_ERROR_TITLE");
				message = localizedWithFormat(@"NO_SEC_KEY_DECRYPT_TEXT_ERROR_MSG", [self descriptionForKeys:missingSecKeys]);
				break;
			}
			default:
				title = ex.reason;
				message = ex.description;
				break;
		}

		[self displayOperationFailedNotificationWithTitle:title message:message];

		return nil;
	} @catch (NSException *localException) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Decryption failed")
												  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];

		return nil;
	}

	// return [[[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] autorelease];
	return [outputData gpgString];
}

- (NSString *)signTextString:(NSString *)inputString {
	GPGController *ctx = [GPGController gpgController];

	ctx.useArmor = YES;

	NSData *inputData = [inputString UTF8Data];

	KeyChooserWindowController *wc = [[KeyChooserWindowController alloc] init];
	GPGKey *chosenKey = wc.selectedKey;

	if (chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
		if ([wc runModal] == 0) {
			chosenKey = wc.selectedKey;
		} else {
			chosenKey = nil;
		}
	}

	if (chosenKey != nil) {
		[ctx addSignerKey:[chosenKey description]];
	} else {
		return nil;
	}

	@try {
		NSData *outputData = [ctx processData:inputData withEncryptSignMode:GPGClearSign recipients:nil hiddenRecipients:nil];

		if (ctx.error) {
			if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
				return nil;
			}
			@throw ctx.error;
		}

		return [outputData gpgString];
	} @catch (GPGException *localException) {
		[self displayOperationFailedNotificationWithTitle:[localException reason]
												  message:[localException description]];
		return nil;
	} @catch (NSException *localException) {
		/*
		 * NSString* errorMessage = nil;
		 * switch(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue]))
		 * {
		 *  case GPGErrorNoData:
		 *      errorMessage = localized(@"No signable text was found within the selection");
		 *      break;
		 *  case GPGErrorBadPassphrase:
		 *      errorMessage = localized(@"The passphrase is incorrect");
		 *      break;
		 *  case GPGErrorUnusableSecretKey:
		 *      errorMessage = localized(@"The default secret key is unusable");
		 *      break;
		 *  case GPGErrorCancelled:
		 *      break;
		 *  default: {
		 *      GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
		 *      errorMessage = GPGErrorDescription(error);
		 *  }
		 * }
		 */
		NSString *errorMessage = [[[localException userInfo] valueForKey:@"gpgTask"] errText];
		if (errorMessage != nil) {
			[self displayOperationFailedNotificationWithTitle:localized(@"Signing failed")
													  message:errorMessage];
		}

		return nil;
	}

	return nil;
}

- (void)verifyTextString:(NSString *)inputString {
	GPGController *ctx = [GPGController gpgController];

	ctx.useArmor = YES;

	@try {
		NSArray *sigs = [ctx verifySignature:[inputString UTF8Data] originalData:nil];

		if ([sigs count] == 0) {
			NSString *retry1 = [inputString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
			sigs = [ctx verifySignature:[retry1 UTF8Data] originalData:nil];
			if ([sigs count] == 0) {
				NSString *retry2 = [inputString stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
				sigs = [ctx verifySignature:[retry2 UTF8Data] originalData:nil];
			}
		}
		if ([sigs count] > 0) {
			GPGSignature *sig = [sigs objectAtIndex:0];
			NSDictionary *result = [self resultForSignature:sig file:nil];
			
			[self displayNotificationWithTitle:result[NOTIFICATION_TITLE_KEY]
									   message:result[NOTIFICATION_MESSAGE_KEY]
										 files:nil
									  userInfo:result
										failed:NO];
		} else {
			// Looks like sigs.count == 0 when we have encrypted text but no signature
			[self displayOperationFailedNotificationWithTitle:localized(@"Verification failed")
													  message:localized(@"No signatures found within the selection")];
		}
	} @catch (NSException *localException) {
		NSLog(@"localException: %@", [localException userInfo]);

		// TODO: Implement correct error handling (might be a problem on libmacgpg's side)
		if ([[[localException userInfo] valueForKey:@"errorCode"] intValue] != GPGErrorNoError) {
			[self displayOperationFailedNotificationWithTitle:localized(@"Verification failed")
													  message:[localException description]];
		}

		/*
		 * if(GPGErrorCodeFromError([[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue])==GPGErrorNoData)
		 *  [self displayOperationFailedNotificationWithTitle:localized(@"Verification failed")
		 *                                            message:localized(@"No verifiable text was found within the selection")];
		 * else {
		 *  GPGError error = [[[localException userInfo] objectForKey:@"GPGErrorKey"] intValue];
		 *  [self displayOperationFailedNotificationWithTitle:localized(@"Verification failed")
		 *                                            message:GPGErrorDescription(error)];
		 * }
		 */
	}
}

#pragma mark -
#pragma mark File Stuff

/**
* @param files Pass in an array of files
* @param singleFileFmt should include %@ for the file name (e.g., "Decrypting %@")
* @param pluralFilesFmt should include %u for [files count] (e.g., "Decrypting %u files")
*/
- (NSString *)describeOperationForFiles:(NSArray *)files
						  singleFileFmt:(NSString *)singleFmt
						 pluralFilesFmt:(NSString *)pluralFmt {
	NSUInteger fcount = [files count];

	if (fcount == 1) {
		NSString *quotedName = [NSString stringWithFormat:@"'%@'",
								[[[files lastObject] lastPathComponent]
								 stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"]];
		return [NSString stringWithFormat:singleFmt, quotedName];
	}
	return [NSString stringWithFormat:pluralFmt, fcount];
}

/**
* @param files Pass in an array of files and successCount
* @param singleFmt should include %@ for the file name (e.g., "Decrypted %@")
* @param singleFailFmt should include %@ for the file name (e.g., "Failed to decrypt %@")
* @param should include %1$u for successCount and %2$u for [files count] (e.g., "Decrypted %1$u of %2$u files")
*/
- (NSString *)describeCompletionForFiles:(NSArray *)files
							successCount:(NSUInteger)successCount
						   singleFileFmt:(NSString *)singleFmt
						   singleFailFmt:(NSString *)singleFailFmt
						  pluralFilesFmt:(NSString *)pluralFmt {
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

- (NSString *)normalizedAndUniquifiedPathFromPath:(NSString *)path {
	NSFileManager *fmgr = [[NSFileManager alloc] init];

	if ([fmgr isWritableFileAtPath:[path stringByDeletingLastPathComponent]]) {
		return [ZKArchive uniquify:path];
	} else {
		NSString *desktop = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory,
																 NSUserDomainMask, YES) objectAtIndex:0];
		return [ZKArchive uniquify:[desktop stringByAppendingPathComponent:[path lastPathComponent]]];
	}
}

- (unsigned long long)sizeOfFile:(NSString *)file {
	NSFileManager *fmgr = [[NSFileManager alloc] init];

	if ([fmgr fileExistsAtPath:file]) {
		NSError *err = nil;
		NSDictionary *fileDictionary = [fmgr attributesOfItemAtPath:file error:&err];

		if ([fileDictionary valueForKey:NSFileType] == NSFileTypeSymbolicLink) {
			NSString *destFile = [fmgr destinationOfSymbolicLinkAtPath:file error:&err];

			if (!err) {
				fileDictionary = [fmgr attributesOfItemAtPath:destFile error:&err];
			} else {
				NSLog(@"error with symbolic link in folderSize: %@", [err description]);
				err = nil;
			}
		}

		if (err) {
			NSLog(@"error in folderSize: %@", [err description]);
		} else {
			return [[fileDictionary valueForKey:NSFileSize] unsignedLongLongValue];
		}
	}

	return 0;
}

- (NSNumber *)folderSize:(NSString *)folderPath {
	NSFileManager *fmgr = [[NSFileManager alloc] init];
	NSArray *filesArray = [fmgr subpathsOfDirectoryAtPath:folderPath error:nil];
	NSEnumerator *filesEnumerator = [filesArray objectEnumerator];
	NSString *fileName = nil;
	unsigned long long int fileSize = 0;

	while ((fileName = [filesEnumerator nextObject]) != nil) {
		fileName = [folderPath stringByAppendingPathComponent:fileName];

		fileSize += [self sizeOfFile:fileName];
	}

	return [NSNumber numberWithUnsignedLongLong:fileSize];
}

- (NSNumber *)sizeOfFiles:(NSArray *)files {
	__block unsigned long long size = 0;

	NSFileManager *fmgr = [[NSFileManager alloc] init];

	[files enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		 NSString *file = (NSString *)obj;
		 BOOL isDirectory = NO;
		 BOOL exists = [fmgr fileExistsAtPath:file isDirectory:&isDirectory];
		 if (exists && isDirectory) {
			 size += [[self folderSize:file] unsignedLongLongValue];
		 } else if (exists) {
			 size += [self sizeOfFile:file];
		 }
	 }];

	return [NSNumber numberWithUnsignedLongLong:size];
}

- (NSString *)detachedSignFileWrapped:(ServiceWrappedArgs *)wrappedArgs file:(NSString *)file withKeys:(NSArray *)keys {
	@try {
		GPGController *ctx = [GPGController gpgController];
		ctx.useArmor = YES;
		wrappedArgs.worker.runningController = ctx;

		for (GPGKey *k in keys) {
			[ctx addSignerKey:[k description]];
		}

		GPGStream *dataToSign = nil;

		if ([[self isDirectoryPredicate] evaluateWithObject:file]) {
			ZipOperation *zipOperation = [[ZipOperation alloc] init];
			zipOperation.filePath = file;
			[zipOperation start];

			// Rename file to <dirname>.zip
			file = [self normalizedAndUniquifiedPathFromPath:[file stringByAppendingPathExtension:@"zip"]];
			if ([zipOperation.zipData writeToFile:file atomically:YES] == NO) {
				return nil;
			}

			dataToSign = [GPGFileStream fileStreamForReadingAtPath:file];
		} else {
			dataToSign = [GPGFileStream fileStreamForReadingAtPath:file];
		}

		if (!dataToSign) {
			[self displayOperationFailedNotificationWithTitle:localized(@"Could not read file")
													  message:file];
			return nil;
		}

		// write to a temporary location in the target directory
		NSError *error = nil;
		GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
								 [file stringByAppendingString:tempTemplate]
													   suffixLen:suffixLen error:&error];
		if (error) {
			[self displayOperationFailedNotificationWithTitle:localized(@"Could not write to directory")
													  message:[file stringByDeletingLastPathComponent]];
			return nil;
		}

		GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];
		[ctx processTo:output data:dataToSign withEncryptSignMode:GPGDetachedSign recipients:nil hiddenRecipients:nil];

		// check after an operation
		if (wrappedArgs.worker.amCanceling) {
			return nil;
		}

		if (ctx.error) {
			if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
				return nil;
			}
			@throw ctx.error;
		}

		if ([output length]) {
			[output close];
			[tempFile closeFile];

			NSString *sigFile = [file stringByAppendingPathExtension:@"sig"];
			sigFile = [self normalizedAndUniquifiedPathFromPath:sigFile];

			error = nil;
			[[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:sigFile error:&error];
			if (!error) {
				tempFile.shouldDeleteFileOnDealloc = NO;
				return sigFile;
			}

			NSLog(@"error while writing to output: %@", error);
			[tempFile deleteFile];
		} else {
			[output close];
			[tempFile deleteFile];
		}
	} @catch (NSException *e) {
		// Ignore exception.
	}

	return nil;
}

- (void)signFiles:(NSArray *)files {
	[self cancelTerminateTimer];
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(signFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Signing %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Signing %u files" /*arg:count*/)];
	[worker start:files];
}

- (void)signFilesSync:(ServiceWrappedArgs *)wrappedArgs {
	@autoreleasepool {

		[self signFilesWrapped:wrappedArgs];
	}
}

- (void)signFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
	// files, though autoreleased, is safe here even when called async
	// because it's retained by ServiceWrappedArgs
	NSArray *files = wrappedArgs.arg1;

	if (files.count == 0) {
		return;
	}

	// check before starting an operation
	if (wrappedArgs.worker.amCanceling) {
		return;
	}
	

	KeyChooserWindowController *wc = [[KeyChooserWindowController alloc] init];
	GPGKey *chosenKey = wc.selectedKey;

	if (chosenKey == nil || [wc.dataSource.keyDescriptions count] > 1) {
		if ([wc runModal] == 0) { // thread-safe
			chosenKey = wc.selectedKey;
		} else {
			return;
		}
	}

	if (chosenKey != nil) {
		
		[self addWorkerToProgressWindow:wrappedArgs.worker];
		
		
		NSMutableArray *signedFiles = [NSMutableArray new];
		NSMutableArray *sigFiles = [NSMutableArray new];

		for (NSString *file in files) {
			// check before starting an operation
			if (wrappedArgs.worker.amCanceling) {
				return;
			}

			NSString *sigFile = [self detachedSignFileWrapped:wrappedArgs
														 file:file withKeys:[NSArray arrayWithObject:chosenKey]];

			// check after an operation
			if (wrappedArgs.worker.amCanceling) {
				return;
			}

			if (sigFile != nil) {
				[signedFiles addObject:file];
				[sigFiles addObject:sigFile];
			}
		}

		NSUInteger innCount = [files count];
		NSUInteger outCount = [signedFiles count];
		NSString *title = (innCount == outCount
						   ? localized(@"Signing finished")
						   : (outCount > 0
							  ? localized(@"Signing finished (partially)")
							  : localized(@"Signing failed")));
		NSString *message = [self describeCompletionForFiles:files
												successCount:outCount
											   singleFileFmt:localized(@"Signed %@" /*arg:filename*/)
											   singleFailFmt:localized(@"Failed signing %@" /*arg:filename*/)
											  pluralFilesFmt:localized(@"Signed %1$u of %2$u files" /*arg1:successCount; arg2:totalCount*/)];
		[self displayOperationFinishedNotificationWithTitle:title
													message:message
													  files:sigFiles];
	}
}

- (void)encryptFiles:(NSArray *)files {
	[self cancelTerminateTimer];
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(encryptFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Encrypting %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Encrypting %u files" /*arg:count*/)];
	[worker start:files];
}

- (void)encryptFilesSync:(ServiceWrappedArgs *)wrappedArgs {
	@autoreleasepool {

		[self encryptFilesWrapped:wrappedArgs];
	}
}

- (void)encryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
	// files, though autoreleased, is safe here even when called async
	// because it's retained by ServiceWrappedArgs
	NSArray *files = wrappedArgs.arg1;

	if (files.count == 0) {
		return;
	}

	if ([self checkFileSizeAndWarn:files] == NO) {
		return;
	}

	
	GPGDebugLog(@"encrypting file(s): %@...", [files componentsJoinedByString:@","]);

	BOOL useASCII = [[[GPGOptions sharedOptions] valueForKey:@"UseASCIIOutput"] boolValue];
	GPGDebugLog(@"Output as ASCII: %@", useASCII ? @"YES" : @"NO");
	NSString *fileExtension = useASCII ? @"asc" : @"gpg";
	RecipientWindowController *rcp = [[RecipientWindowController alloc] init];
	NSInteger ret = [rcp runModal]; // thread-safe
	if (ret != 0) {
		return;  // User pressed 'cancel'
	}
	NSSet *validRecipients = rcp.selectedKeys;
	GPGKey *privateKey = rcp.selectedPrivateKey;

	if (rcp.encryptForOwnKeyToo) {
		validRecipients = [validRecipients setByAddingObject:privateKey];
	}

	GPGEncryptSignMode mode = (rcp.sign ? GPGSign : 0) | (validRecipients.count ? GPGPublicKeyEncrypt : 0) | (rcp.symetricEncryption ? GPGSymetricEncrypt : 0);


	// check before starting an operation
	if (wrappedArgs.worker.amCanceling) {
		return;
	}
	
	[self addWorkerToProgressWindow:wrappedArgs.worker];

	long double megabytes = 0;
	NSString *destination = nil;
	NSString *originalName = nil;

	NSFileManager *fmgr = [[NSFileManager alloc] init];

	typedef GPGStream *(^DataProvider)(void);
	DataProvider dataProvider;

	if (files.count == 1) {
		NSString *file = [files objectAtIndex:0];
		BOOL isDirectory = YES;

		if (![fmgr fileExistsAtPath:file isDirectory:&isDirectory]) {
			[self displayOperationFailedNotificationWithTitle:localized(@"File doesn't exist")
													  message:localized(@"Please try again")];
			return;
		}
		if (isDirectory) {
			originalName = [NSString stringWithFormat:@"%@.zip", [file lastPathComponent]];
			megabytes = [[self folderSize:file] unsignedLongLongValue] / kBytesInMB;
			destination = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:[originalName stringByAppendingString:@".gpg"]];
			dataProvider = ^{
				ZipOperation *operation = [[ZipOperation alloc] init];
				operation.filePath = file;
				operation.delegate = self;
				[operation start];

				return [GPGMemoryStream memoryStreamForReading:operation.zipData];
			};
		} else {
			NSNumber *fileSize = [self sizeOfFiles:[NSArray arrayWithObject:file]];
			megabytes = [fileSize unsignedLongLongValue] / kBytesInMB;
			originalName = [file lastPathComponent];
			destination = [file stringByAppendingFormat:@".%@", fileExtension];
			dataProvider = ^{
				return [GPGFileStream fileStreamForReadingAtPath:file];
			};
		}
	} else if (files.count > 1) {
		megabytes = [[self sizeOfFiles:files] unsignedLongLongValue] / kBytesInMB;
		originalName = [localized(@"Archive" /*Filename for Archive.zip.gpg*/) stringByAppendingString:@".zip"];
		destination = [[[files objectAtIndex:0] stringByDeletingLastPathComponent]
						stringByAppendingPathComponent:[originalName stringByAppendingString:@".gpg"]];
		dataProvider = ^{
			ZipOperation *operation = [[ZipOperation alloc] init];
			operation.files = files;
			operation.delegate = self;
			[operation start];

			return [GPGMemoryStream memoryStreamForReading:operation.zipData];
		};
	}

	GPGDebugLog(@"fileSize: %@Mb", [NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithDouble:megabytes]
																	numberStyle:NSNumberFormatterDecimalStyle]);

	NSAssert(dataProvider != nil, @"dataProvider can't be nil");
	NSAssert(destination != nil, @"destination can't be nil");

	// check before starting an operation
	if (wrappedArgs.worker.amCanceling) {
		return;
	}

	GPGController *ctx = [GPGController gpgController];
	
	ctx.trustAllKeys = YES;
	// Only use armor for single files. otherwise it doesn't make much sense.
	ctx.useArmor = useASCII && [destination rangeOfString:@".asc"].location != NSNotFound;
	wrappedArgs.worker.runningController = ctx;
	
	ctx.forceFilename = originalName;

	GPGStream *gpgData = dataProvider();

	// write to a temporary location in the target directory
	NSError *error = nil;
	GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
							 [destination stringByAppendingString:tempTemplate]
												   suffixLen:suffixLen error:&error];
	if (error) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Could not write to directory")
												  message:[destination stringByDeletingLastPathComponent]];
		return;
	}

	GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];

	@try {
		if (mode & GPGSign) {
			[ctx addSignerKey:[privateKey description]];
		}

		[ctx processTo:output
						data:gpgData
		 withEncryptSignMode:mode
				  recipients:validRecipients
			hiddenRecipients:nil];

		// check after a lengthy operation
		if (wrappedArgs.worker.amCanceling) {
			return;
		}

		if (ctx.error) {
			if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
				return;
			}
			@throw ctx.error;
		}
	} @catch (GPGException *localException) {
		[self displayOperationFailedNotificationWithTitle:[localException reason]
												  message:[localException description]];
		return;
	} @catch (NSException *localException) {
		[self displayOperationFailedNotificationWithTitle:localized(@"Encryption failed")
												  message:[[[localException userInfo] valueForKey:@"gpgTask"] errText]];
		return;
	}

	// Check if directory is writable and append i+1 if file already exists at destination
	destination = [self normalizedAndUniquifiedPathFromPath:destination];
	GPGDebugLog(@"destination: %@", destination);

	[output close];
	[tempFile closeFile];
	error = nil;
	[[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:destination error:&error];
	if (error) {
		[tempFile deleteFile];
		// We should probably show the file from the exception too.
		[self displayOperationFailedNotificationWithTitle:localized(@"Encryption failed")
												  message:[destination lastPathComponent]];
		return;
	}

	tempFile.shouldDeleteFileOnDealloc = NO;
	[self displayOperationFinishedNotificationWithTitle:localized(@"Encryption finished")
												message:[destination lastPathComponent]
												  files:@[destination]];
}

- (void)decryptFiles:(NSArray *)files {
	[self cancelTerminateTimer];
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(decryptFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Decrypting %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Decrypting %u files" /*arg:count*/)];
	[self addWorkerToProgressWindow:worker];
	[worker start:files];
}

- (void)decryptFilesSync:(ServiceWrappedArgs *)wrappedArgs {
	@autoreleasepool {

		[self decryptFilesWrapped:wrappedArgs];
	}
}

- (void)decryptFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
	// files, though autoreleased, is safe here even when called async
	// because it's retained by ServiceWrappedArgs
	NSArray *files = wrappedArgs.arg1;

	if (files.count == 0) {
		return;
	}


	NSFileManager *fmgr = [NSFileManager defaultManager];
	NSMutableArray *decryptedFiles = [NSMutableArray new];
	NSMutableArray *signedFiles = [NSMutableArray new];
	NSMutableArray<NSDictionary *> *errors = [NSMutableArray new];
	NSUInteger cancelledCount = 0;
	
	NSMutableArray *allVerificationResults = [NSMutableArray new];
	NSString *identifier = [NSUUID UUID].UUIDString; // A random identifier for this operation.
	__block DummyVerificationController *verificationController = nil;
	

	for (NSString *file in files) {
		// check before starting an operation
		if (wrappedArgs.worker.amCanceling) {
			return;
		}

		BOOL isDirectory = NO;
		@try {
			if ([fmgr fileExistsAtPath:file isDirectory:&isDirectory] &&
				isDirectory == NO) {
				GPGFileStream *input = [GPGFileStream fileStreamForReadingAtPath:file];
				GPGDebugLog(@"inputData.size: %llu", [input length]);

				// write to a temporary location in the target directory
				NSError *error = nil;
				GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:[file stringByAppendingString:tempTemplate]
															   suffixLen:suffixLen error:&error];
				if (error) {
					[self displayOperationFailedNotificationWithTitle:localized(@"Could not write to directory")
															  message:[file stringByDeletingLastPathComponent]];
					return;
				}

				GPGFileStream *output = [GPGFileStream fileStreamForWritingAtPath:tempFile.fileName];
				
				GPGController *ctx = [GPGController gpgController];
				wrappedArgs.worker.runningController = ctx;
				ctx.userInfo = @{@"type": @"file"};
				ctx.delegate = self;
				
				[ctx decryptTo:output data:input];
				[output close];
				[tempFile closeFile];
				
				// check again after a potentially long operation
				if (wrappedArgs.worker.amCanceling) {
					[tempFile deleteFile];
					return;
				}
				if ([ctx.userInfo[@"cancelled"] boolValue]) {
					// The user choosed to cancel this file decryption.
					cancelledCount++;
					[tempFile deleteFile];
					continue;
				}
				

				if (ctx.error) {
					[tempFile deleteFile];
					if ([ctx.error respondsToSelector:@selector(errorCode)] && [(GPGException *)ctx.error errorCode] == GPGErrorCancelled) {
						return;
					}
					@throw ctx.error;
				}

				
				
				NSString *outputFile;
				NSString *fileName = nil;
				if ([ctx.statusDict[@"PLAINTEXT"] count] > 0 && [ctx.statusDict[@"PLAINTEXT"][0] count] > 2) {
					fileName = ctx.statusDict[@"PLAINTEXT"][0][2];
				}
				if (fileName.length && ![fileName isEqualToString:@"_CONSOLE"] && [fileName rangeOfString:@"/"].length == 0) {
					fileName = [fileName stringByRemovingPercentEncoding];
					outputFile = [[file stringByDeletingLastPathComponent] stringByAppendingPathComponent:fileName];
				} else {
					outputFile = [file stringByDeletingPathExtension];
				}
				
				outputFile = [self normalizedAndUniquifiedPathFromPath:outputFile];
				
				
				[[NSFileManager defaultManager] moveItemAtPath:tempFile.fileName toPath:outputFile error:&error];
				if (error) {
					NSLog(@"error while writing to output: %@", error);
					[tempFile deleteFile];
				} else {
					tempFile.shouldDeleteFileOnDealloc = NO;
					[decryptedFiles addObject:outputFile];
				}
				

				
				
				
				
				if (!verificationController) {
					// A click on a notification can show a verification controller. Get that controller, if it exists already.
					NSDictionary *verificationOperation = [self verificationOperationForKey:identifier];
					DummyVerificationController *tmp = verificationOperation[VERIFICATION_CONTROLLER_KEY];
					if (tmp) {
						verificationController = tmp;
					}
				}
				
				NSArray *results = [self verificationResultsFromSigs:ctx.signatures forFile:outputFile];
				[allVerificationResults addObjectsFromArray:results];
				
				// Add the results to a, possible existing, verification controller. Most likely verificationController is nil here.
				[verificationController addResults:results];

				[self setVerificationOperation:[NSDictionary dictionaryWithObjectsAndKeys:
												allVerificationResults.copy, ALL_VERIFICATION_RESULTS_KEY,
												verificationController, VERIFICATION_CONTROLLER_KEY, nil]
										forKey:identifier];

				if (ctx.signatures.count > 0) {
					[signedFiles addObject:outputFile];
					[self displayNotificationWithVerficationResults:results
														fullResults:allVerificationResults
												operationIdentifier:identifier
												  completionHandler:^(BOOL notificationDidShow) {
						if (!notificationDidShow && !verificationController) {
							// Can't show notifications and no verification controller is visible.
							// Show a new verification controller.
							verificationController = [DummyVerificationController verificationController]; // thread-safe
							[verificationController addResults:allVerificationResults];
							
							// Remember the controller for this operation.
							[self setVerificationOperation:[NSDictionary dictionaryWithObjectsAndKeys:
															allVerificationResults.copy, ALL_VERIFICATION_RESULTS_KEY,
															verificationController, VERIFICATION_CONTROLLER_KEY, nil]
													forKey:identifier];
						}
					}];
				}
				
			}
		} @catch (NSException *ex) {
			[errors addObject:@{@"exception": ex, @"file": file}];
		}
	}

	
	NSUInteger innCount = [files count];
	NSUInteger outCount = [decryptedFiles count];

	if (cancelledCount == innCount) {
		// All files where cancelled. Do not show a summary.
		return;
	}
	
	
	
	

	NSString *title;
	NSString *message;
	if (innCount == outCount) {
		title = localized(@"Decryption finished");
	} else if (outCount > 0) {
		title = localized(@"Decryption finished (partially)");
	} else {
		title = localized(@"Decryption failed");
	}
	
	
	NSMutableArray *errorMsgs = [NSMutableArray new];
	BOOL showDefaultMessage = YES;
	
	if (innCount == outCount && // All files are successfully decrypted
		[decryptedFiles isEqualToArray:signedFiles]) { // and all of them are signed.
		
		// Do not show a additional notification, because for every files there was already a verification notification.
		
		showDefaultMessage = NO;
	} else if (innCount == 1 && outCount == 0 && errors.count == 1) {
		// Error messages for a single failed decryption.
		
		GPGException *ex = errors[0][@"exception"];
		if ([ex isKindOfClass:[GPGException class]]) {
			NSString *file = errors[0][@"file"];

			switch (ex.errorCode) {
				case GPGErrorNoSecretKey: {
					NSMutableArray *missingSecKeys = [NSMutableArray new];
					NSArray *missingKeys = ex.gpgTask.statusDict[@"NO_SECKEY"]; //Array of Arrays of String!
					NSUInteger count = missingKeys.count;
					NSUInteger i = 0;
					for (; i < count; i++) {
						[missingSecKeys addObject:missingKeys[i][0]];
					}

					title = localizedWithFormat(@"NO_SEC_KEY_DECRYPT_FILE_ERROR_TITLE", file.lastPathComponent);
					message = localizedWithFormat(@"NO_SEC_KEY_DECRYPT_FILE_ERROR_MSG", [self descriptionForKeys:missingSecKeys]);
					showDefaultMessage = NO;
					break;
				}
				default:
					break;
			}
		}
	}
	
	
	
	if (showDefaultMessage) {
		for (NSDictionary *dict in errors) {
			NSException *ex = dict[@"exception"];
			NSString *file = dict[@"file"];
			NSString *msg;
			
			if ([ex isKindOfClass:[GPGException class]]) {
				msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
			} else {
				msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent],
					   localized(@"Unexpected decrypt error")];
				NSLog(@"decryptData ex: %@", ex);
			}
			
			[errorMsgs addObject:msg];
		}

		NSMutableString *mutableMessage = [NSMutableString stringWithString:
									[self describeCompletionForFiles:files
														successCount:outCount
													   singleFileFmt:localized(@"Decrypted %@" /*arg:filename*/)
													   singleFailFmt:localized(@"Failed decrypting %@" /*arg:filename*/)
													  pluralFilesFmt:localized(@"Decrypted %1$u of %2$u files" /*arg1:successCount arg2:totalCount*/)]];
		if (errorMsgs.count) {
			[mutableMessage appendString:@"\n\n"];
			[mutableMessage appendString:[errorMsgs componentsJoinedByString:@"\n"]];
		}
		
		message = mutableMessage;
	}

	
	[self displayOperationFinishedNotificationWithTitle:title
												message:message
												  files:decryptedFiles.copy];
	
}

- (void)verifyFiles:(NSArray *)files {
	[self cancelTerminateTimer];
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(verifyFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Verifying signature of %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Verifying signatures of %u files" /*arg:count*/)];
	[self addWorkerToProgressWindow:worker];
	[worker start:files];
}

- (void)verifyFilesSync:(ServiceWrappedArgs *)wrappedArgs {
	@autoreleasepool {

		[self verifyFilesWrapped:wrappedArgs];
	}
}

- (void)verifyFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {

	// files, though autoreleased, is safe here even when called async
	// because it's retained by NSOperation that is wrapping the process
	NSArray *files = wrappedArgs.arg1;

	NSMutableSet *filesInVerification = [NSMutableSet new];
	NSFileManager *fmgr = [NSFileManager defaultManager];
	NSMutableArray *allVerificationResults = [NSMutableArray new];
	NSString *identifier = [NSUUID UUID].UUIDString; // A random identifier for this operation.
	__block DummyVerificationController *verificationController = nil;
	

	for (NSString *serviceFile in files) {
		// check before operation
		if (wrappedArgs.worker.amCanceling) {
			return;
		}

		// Do the file stuff here to be able to check if file is already in verification
		NSString *signedFile = serviceFile;
		NSString *signatureFile = [GPGServices searchSignatureFileForFile:signedFile];
		if (signatureFile == nil) {
			signatureFile = serviceFile;
			signedFile = [GPGServices searchFileForSignatureFile:signatureFile];
		}
		if (signedFile == nil) {
			signedFile = serviceFile;
			signatureFile = nil;
		}

		if (signatureFile != nil) {
			if ([filesInVerification containsObject:signatureFile]) {
				continue;
			}

			// Probably a problem with restarting of validation when files are missing
			[filesInVerification addObject:signatureFile];
		}

		NSException *firstException = nil;
		NSException *secondException = nil;

		NSArray *sigs = nil;

		if ([fmgr fileExistsAtPath:signedFile] && [fmgr fileExistsAtPath:signatureFile]) {
			@try {
				GPGController *ctx = [GPGController gpgController];
				wrappedArgs.worker.runningController = ctx;

				GPGFileStream *signatureInput = [GPGFileStream fileStreamForReadingAtPath:signatureFile];
				GPGFileStream *originalInput = [GPGFileStream fileStreamForReadingAtPath:signedFile];
				sigs = [ctx verifySignatureOf:signatureInput originalData:originalInput];
			} @catch (NSException *exception) {
				firstException = exception;
				sigs = nil;
			}

			// check after operation
			if (wrappedArgs.worker.amCanceling) {
				return;
			}
		}

		// Try to verify the file itself without a detached sig
		if (sigs == nil || sigs.count == 0) {
			@try {
				GPGController *ctx = [GPGController gpgController];
				wrappedArgs.worker.runningController = ctx;

				GPGFileStream *signedInput = [GPGFileStream fileStreamForReadingAtPath:serviceFile];
				sigs = [ctx verifySignatureOf:signedInput originalData:nil];
			} @catch (NSException *exception) {
				secondException = exception;
				sigs = nil;
			}

			// check after operation
			if (wrappedArgs.worker.amCanceling) {
				return;
			}
		}

		
		
		
		if (!verificationController) {
			// A click on a notification can show a verification controller. Get that controller, if it exists already.
			NSDictionary *verificationOperation = [self verificationOperationForKey:identifier];
			DummyVerificationController *tmp = verificationOperation[VERIFICATION_CONTROLLER_KEY];
			if (tmp) {
				verificationController = tmp;
			}
		}
		
		
		NSArray *results = [self verificationResultsFromSigs:sigs forFile:signedFile];
		[allVerificationResults addObjectsFromArray:results];
		
		// Add the results to a, possible existing, verification controller. Most likely verificationController is nil here.
		[verificationController addResults:results];
		
		[self setVerificationOperation:[NSDictionary dictionaryWithObjectsAndKeys:
										allVerificationResults.copy, ALL_VERIFICATION_RESULTS_KEY,
										verificationController, VERIFICATION_CONTROLLER_KEY, nil]
								forKey:identifier];
		
		
		[self displayNotificationWithVerficationResults:results
											fullResults:allVerificationResults
									operationIdentifier:identifier
									  completionHandler:^(BOOL notificationDidShow) {
			if (!notificationDidShow && !verificationController) {
				// Can't show notifications and no verification controller is visible.
				// Show a new verification controller.
				verificationController = [DummyVerificationController verificationController]; // thread-safe
				[verificationController addResults:allVerificationResults];
				
				// Remember the controller for this operation.
				[self setVerificationOperation:[NSDictionary dictionaryWithObjectsAndKeys:
												allVerificationResults.copy, ALL_VERIFICATION_RESULTS_KEY,
												verificationController, VERIFICATION_CONTROLLER_KEY, nil]
										forKey:identifier];
			}
		}];
		
	}
	
}

- (void)importFiles:(NSArray *)files {
	[self cancelTerminateTimer];
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(importFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Importing %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Importing %u files" /*arg:count*/)];
	[self addWorkerToProgressWindow:worker];
	[worker start:files];
}

- (void)importFilesSync:(ServiceWrappedArgs *)wrappedArgs {
	@autoreleasepool {

		[self importFilesWrapped:wrappedArgs];
	}
}

- (void)importFilesWrapped:(ServiceWrappedArgs *)wrappedArgs {
	// files, though autoreleased, is safe here even when called async
	// because it's retained by ServiceWrappedArgs
	NSArray *files = wrappedArgs.arg1;

	if ([files count] < 1) {
		return;
	}

	GPGController *gpgc = [GPGController gpgController];
	wrappedArgs.worker.runningController = gpgc;

	NSMutableArray *importedFiles = [NSMutableArray arrayWithCapacity:[files count]];
	NSMutableArray *errorMsgs = [NSMutableArray array];

	for (NSString *file in files) {
		// check before starting an operation
		if (wrappedArgs.worker.amCanceling) {
			return;
		}

		if ([[self isDirectoryPredicate] evaluateWithObject:file] == YES) {
			NSString *msg = [NSString stringWithFormat:localized(@"%@ — Cannot import directory" /*arg:path*/),
							 [file lastPathComponent]];
			[errorMsgs addObject:msg];
			continue;
		}

		NSData *data = [NSData dataWithContentsOfFile:file];
		@try {
			/*NSString* inputText = */ [gpgc importFromData:data fullImport:NO];

			// check after an operation
			if (wrappedArgs.worker.amCanceling) {
				return;
			}

			if (gpgc.error) {
				@throw gpgc.error;
			}

			[importedFiles addObject:file];
		} @catch (NSException *ex) {
			NSString *msg;
			if ([ex isKindOfClass:[GPGException class]]) {
				msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent], ex];
			} else {
				msg = [NSString stringWithFormat:@"%@ — %@", [file lastPathComponent],
					   localized(@"Unexpected import error")];
				NSLog(@"importFromData ex: %@", ex);
			}
			[errorMsgs addObject:msg];
		}
	}

	NSUInteger innCount = [files count];
	NSUInteger outCount = [importedFiles count];
	NSString *title = (innCount == outCount
					   ? localized(@"Import finished")
					   : (outCount > 0
						  ? localized(@"Import finished (partially)")
						  : localized(@"Import failed")));
	NSMutableString *message = [NSMutableString stringWithString:
								[self describeCompletionForFiles:files
													successCount:outCount
												   singleFileFmt:localized(@"Imported %@" /*arg:filename*/)
												   singleFailFmt:localized(@"Failed importing %@" /*arg:filename*/)
												  pluralFilesFmt:localized(@"Imported %1$u of %2$u files" /*arg1:successCount arg2:totalCount*/)]];
	if ([errorMsgs count]) {
		[message appendString:@"\n\n"];
		[message appendString:[errorMsgs componentsJoinedByString:@"\n"]];
	}
	[self displayOperationFinishedNotificationWithTitle:title
												message:message];
}

#pragma mark - ServiceWorkerDelegate

- (void)workerWasCanceled:(id)worker {
	[self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)workerDidFinish:(id)worker {
	[self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)removeWorker:(id)worker {
	[self goneIn60Seconds];
	[_inProgressCtlr removeObjectFromServiceWorkerArray:worker];
	if ([_inProgressCtlr.serviceWorkerArray count] < 1) {
		[_inProgressCtlr.window orderOut:nil];
	}
}

#pragma mark - NSPredicates for filtering file arrays

- (NSPredicate *)fileExistsPredicate {
	NSFileManager *fmgr = [[NSFileManager alloc] init];

	return [[NSPredicate predicateWithBlock:^BOOL (id file, NSDictionary *bindings) {
				  return [file isKindOfClass:[NSString class]] && [fmgr fileExistsAtPath:file];
			  }] copy];
}

- (NSPredicate *)isDirectoryPredicate {
	NSFileManager *fmgr = [[NSFileManager alloc] init];

	return [[NSPredicate predicateWithBlock:^BOOL (id file, NSDictionary *bindings) {
				  BOOL isDirectory = NO;
				  return [file isKindOfClass:[NSString class]] &&
				  [fmgr fileExistsAtPath:file isDirectory:&isDirectory] &&
				  isDirectory;
			  }] copy];
}

#pragma mark -
#pragma mark Service handling routines

- (void)dealWithPasteboard:(NSPasteboard *)pboard
				  userData:(NSString *)userData
					  mode:(ServiceModeEnum)mode
					 error:(NSString **)error {
	[self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
	
	
	@try {
		
		NSString *pboardString = nil, *pbtype = nil;
		if (mode != MyKeyService && mode != MyFingerprintService) {
			pbtype = [pboard availableTypeFromArray:[NSArray arrayWithObjects:
													 NSPasteboardTypeString,
													 NSPasteboardTypeRTF,
													 nil]];
			NSString *myerror = localized(@"GPGServices did not get usable data from the pasteboard." /*Pasteboard could not supply the string in an acceptible format.*/);
			
			if ([pbtype isEqualToString:NSPasteboardTypeString]) {
				if (!(pboardString = [pboard stringForType:NSPasteboardTypeString])) {
					*error = myerror;
					return;
				}
			} else if ([pbtype isEqualToString:NSPasteboardTypeRTF]) {
				if (!(pboardString = [pboard stringForType:NSPasteboardTypeString])) {
					*error = myerror;
					return;
				}
			} else {
				*error = myerror;
				return;
			}
			
			if ([pboardString rangeOfString:@"\xC2\xA0"].length > 0) {
				// Replace non-breaking space with a normal space.
				NSString *temp = [pboardString stringByReplacingOccurrencesOfString:@"\xC2\xA0" withString:@" "];
				pboardString = temp ? temp : pboardString;
			}
		}
		
		NSString *newString = nil;
		switch (mode) {
			case SignService:
				newString = [self signTextString:pboardString];
				break;
			case EncryptService:
				newString = [self encryptTextString:pboardString];
				break;
			case DecryptService:
				newString = [self decryptTextString:pboardString];
				break;
			case VerifyService:
				[self verifyTextString:pboardString];
				break;
			case MyKeyService:
				newString = [self myKey];
				break;
			case MyFingerprintService:
				newString = [self myFingerprint];
				break;
			case ImportKeyService:
				[self importKey:pboardString];
				break;
			default:
				break;
		}
		
		
		if (newString != nil) {
			static NSString *const kServiceShowInWindow = @"showInWindow";
			if ([userData isEqualToString:kServiceShowInWindow]) {
				[self cancelTerminateTimer];
				[SimpleTextWindow showText:newString withTitle:@"GPGServices" andDelegate:self];
			} else {
				[pboard clearContents];
				
				NSMutableArray *pbitems = [NSMutableArray array];
				
				if ([pbtype isEqualToString:NSPasteboardTypeHTML]) {
					NSPasteboardItem *htmlItem = [[NSPasteboardItem alloc] init];
					if (!htmlItem) {
						NSLog(@"Unable to create htmlItem!");
						[NSException raise:NSGenericException format:@"Unable to create htmlItem!"];
					}
					[htmlItem setString:[newString stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"]
								forType:NSPasteboardTypeHTML];
					[pbitems addObject:htmlItem];
				} else if ([pbtype isEqualToString:NSPasteboardTypeRTF]) {
					NSPasteboardItem *rtfItem = [[NSPasteboardItem alloc] init];
					if (!rtfItem) {
						NSLog(@"Unable to create rtfItem!");
						[NSException raise:NSGenericException format:@"Unable to create rtfItem!"];
					}
					[rtfItem setString:newString forType:NSPasteboardTypeRTF];
					[pbitems addObject:rtfItem];
				} else {
					NSPasteboardItem *stringItem = [[NSPasteboardItem alloc] init];
					if (!stringItem) {
						NSLog(@"Unable to create stringItem!");
						[NSException raise:NSGenericException format:@"Unable to create stringItem!"];
					}
					[stringItem setString:newString forType:NSPasteboardTypeString];
					[pbitems addObject:stringItem];
				}
				
				[pboard writeObjects:pbitems];
			}
		}
		
	} @catch (NSException *exception) {
		NSLog(@"An exception(1) occured: '%@'\nException class: %@\nBacktrace: '%@'",
			  exception.description, exception.className, exception.callStackSymbols);
		GPGDebugLog(@"Pasteboard: '%@'\nuserData: '%@'\nmode: %i", pboard, userData, mode);
	} @finally {
		[self goneIn60Seconds];
	}
	
}

- (void)dealWithFilesPasteboard:(NSPasteboard *)pboard
					   userData:(NSString *)userData
						   mode:(FileServiceModeEnum)mode
						  error:(NSString **)error {
	[self cancelTerminateTimer];
	[NSApp activateIgnoringOtherApps:YES];
	
	@try {
		
		NSData *data = [pboard dataForType:NSFilenamesPboardType];
		
		
		NSError *serializationError = nil;
		NSArray *filenames = nil;
		
		if (!data) {
			serializationError = [NSError errorWithDomain:@"GPGServices" code:1 userInfo:@{NSLocalizedDescriptionKey: @"No files found!"}];
		} else {
			filenames = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:&serializationError];
		}
		
		
		if (serializationError) {
			NSLog(@"error while getting files form pboard: %@", serializationError);
			*error = [serializationError localizedDescription];
		} else {
			filenames = [[NSSet setWithArray:filenames] allObjects];
			
			switch (mode) {
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
		
	} @catch (NSException *exception) {
		NSLog(@"An exception(2) occured: '%@'\nException class: %@\nBacktrace: '%@'",
			  exception.description, exception.className, exception.callStackSymbols);
		GPGDebugLog(@"Pasteboard: '%@'\nuserData: '%@'\nmode: %i", pboard, userData, mode);
	} @finally {
		[self goneIn60Seconds];
	}

}

- (void)sign:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:SignService error:error];
}

- (void)encrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:EncryptService error:error];
}

- (void)decrypt:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:DecryptService error:error];
}

- (void)verify:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:VerifyService error:error];
}

- (void)myKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:MyKeyService error:error];
}

- (void)myFingerprint:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:MyFingerprintService error:error];
}

- (void)importKey:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithPasteboard:pboard userData:userData mode:ImportKeyService error:error];
}

- (void)signFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithFilesPasteboard:pboard userData:userData mode:SignFileService error:error];
}

- (void)encryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithFilesPasteboard:pboard userData:userData mode:EncryptFileService error:error];
}

- (void)decryptFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithFilesPasteboard:pboard userData:userData mode:DecryptFileService error:error];
}

- (void)validateFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithFilesPasteboard:pboard userData:userData mode:VerifyFileService error:error];
}

- (void)importFile:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	[self dealWithFilesPasteboard:pboard userData:userData mode:ImportFileService error:error];
}



#pragma mark -
#pragma mark UI Helper

- (void)addWorkerToProgressWindow:(ServiceWorker *)worker {
	[self performSelectorOnMainThread:@selector(addWorkerToProgressWindowOnMain:) withObject:worker waitUntilDone:NO];
}
- (void)addWorkerToProgressWindowOnMain:(ServiceWorker *)worker {
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr delayedShowWindow];
}


- (NSURL *)getFilenameForSavingWithSuggestedPath:(NSString *)path
						  withSuggestedExtension:(NSString *)ext {
	NSSavePanel *savePanel = [NSSavePanel savePanel];

	savePanel.title = localized(@"Choose Destination" /*for saving a file*/);
	savePanel.directoryURL = [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]];
	

	if (ext == nil) {
		ext = @".gpg";
	}
	[savePanel setNameFieldStringValue:[[path lastPathComponent]
										stringByAppendingString:ext]];

	if ([savePanel runModal] == NSModalResponseOK) {
		return savePanel.URL;
	} else {
		return nil;
	}
}



- (void)simpleTextWindowWillClose:(SimpleTextWindow *)simpleTextWindow {
	[self goneIn60Seconds];
}

//
// Timer based application termination
//
- (void)cancelTerminateTimer {
	terminateCounter++;
	[currentTerminateTimer invalidate];
	currentTerminateTimer = nil;
}

- (void)goneIn60Seconds {
	terminateCounter--;
	if (currentTerminateTimer != nil) {
		// Shouldn't happen.
		[self cancelTerminateTimer];
		terminateCounter--;
	}
	if (terminateCounter <= 0) {
		terminateCounter = 0;
		[NSApp hide:self];
		currentTerminateTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self selector:@selector(selfQuit:) userInfo:nil repeats:YES];
	}
}

- (void)selfQuit:(NSTimer *)timer {
	if (_inProgressCtlr.serviceWorkerArray.count < 1) {
		[self cancelTerminateTimer];
		[NSApp terminate:self];
	}
}



- (BOOL)checkFileSizeAndWarn:(NSArray *)files {
	// This method calculates the size of all files and directories given,
	// and warns if they are bigger than warningSize.
	// Returns NO if the user decides to cancel.
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSInteger warningSize = 100 * 1024 * 1024;
	
	
	for (NSString *file in files) {
		NSDictionary *attributes = [fileManager attributesOfItemAtPath:file error:nil];
		
		if ([attributes.fileType isEqualToString:NSFileTypeDirectory]) {
			NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:file]
			  includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsDirectoryKey]
								 options:0
							errorHandler:nil];
			
			for (NSURL *url in directoryEnumerator) {
				NSNumber *isDirectory;
				[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
				
				if (isDirectory.boolValue) {
					continue;
				}
				
				NSNumber *size;
				[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
				
				warningSize -= size.unsignedLongLongValue;
				if (warningSize <= 0) {
					break;
				}
			}
		} else {
			warningSize -= attributes.fileSize;
		}
		
		if (warningSize <= 0) {
			break;
		}
	}
	
	if (warningSize <= 0) {
		__block BOOL result = YES;
		
		void (^alertBlock)(void) = ^{
			NSAlert *alert = [NSAlert new];
			
			alert.messageText = localized(@"BIG_FILE_ENCRYPTION_WARNING_TITLE");
			alert.informativeText = localized(@"BIG_FILE_ENCRYPTION_WARNING_MSG");
			[alert addButtonWithTitle:localized(@"BIG_FILE_ENCRYPTION_WARNING_BUTTON1")];
			[alert addButtonWithTitle:localized(@"BIG_FILE_ENCRYPTION_WARNING_BUTTON2")];
			
			[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
			
			if (alert.runModal != NSAlertSecondButtonReturn) {
				result = NO;
			}
		};
		
		if ([NSThread isMainThread]) {
			alertBlock();
		} else {
			dispatch_sync(dispatch_get_main_queue(), alertBlock);
		}
		
		if (!result) {
			return NO;
		}
	}
	
	return YES;
}

- (BOOL)gpgControllerShouldDecryptWithoutMDC:(GPGController *)gpgc {
	
	if (gpgc.signatures.count > 0) {
		GPGSignature *signature = gpgc.signatures[0];
		// Allow messages without mdc, if there is a trusted signature.
		if (signature.trust < GPGValidityInvalid && signature.trust >= GPGValidityFull) {
			return YES;
		}
	}
	
	__block BOOL shouldDecryptWithoutMDC = NO;
	
	void (^alertBlock)(void) = ^{
		NSAlert *alert = [NSAlert new];
		
		NSString *baseString = [gpgc.userInfo[@"type"] isEqualToString:@"file"] ? @"NO_MDC_DECRYPT_FILE_WARNING_" : @"NO_MDC_DECRYPT_TEXT_WARNING_";
		
		alert.messageText = localized([baseString stringByAppendingString:@"TITLE"]);
		alert.informativeText = localized([baseString stringByAppendingString:@"MSG"]);
		[alert addButtonWithTitle:localized([baseString stringByAppendingString:@"NO"])];
		[alert addButtonWithTitle:localized([baseString stringByAppendingString:@"YES"])];
		
		[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
		
		if (alert.runModal == NSAlertSecondButtonReturn) {
			shouldDecryptWithoutMDC = YES;
		}
	};
	
	if ([NSThread isMainThread]) {
		alertBlock();
	} else {
		dispatch_sync(dispatch_get_main_queue(), alertBlock);
	}
	
	if (!shouldDecryptWithoutMDC) {
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:gpgc.userInfo];
		userInfo[@"cancelled"] = @YES;
		gpgc.userInfo = userInfo;
	}
	
	return shouldDecryptWithoutMDC;
}


- (NSString *)descriptionForKeys:(NSArray *)keys {
	NSMutableString *descriptions = [NSMutableString string];
	Class gpgKeyClass = [GPGKey class];
	NSUInteger i = 0, count = keys.count;
	NSUInteger lines = 10;
	if (count == 0) {
		return @"";
	}
	if (lines > 0 && count > lines) {
		lines = lines - 1;
	} else {
		lines = NSUIntegerMax;
	}
	BOOL singleKey = count == 1;
	BOOL indent = NO;
	
	
	NSString *lineBreak = indent ? @"\n\t" : @"\n";
	if (indent) {
		[descriptions appendString:@"\t"];
	}
	
	NSString *normalSeperator = [@"," stringByAppendingString:lineBreak];
	NSString *lastSeperator = [NSString stringWithFormat:@" %@%@", localized(@"and"), lineBreak];
	NSString *seperator = @"";
	
	for (__strong GPGKey *key in keys) {
		if (i >= lines && i > 0) {
			[descriptions appendFormat:localized(@"KeyDescriptionAndMore"), lineBreak , count - i];
			break;
		}
		
		if (![key isKindOfClass:gpgKeyClass]) {
			NSString *keyID = (id)key;
			GPGKeyManager *keyManager = [GPGKeyManager sharedInstance];
			GPGKey *realKey = nil;
			if (keyID.length == 16) {
				realKey = keyManager.keysByKeyID[keyID];
			} else {
				realKey = [keyManager.allKeysAndSubkeys member:key];
			}

			if (!realKey) {
				realKey = [[keyManager keysByKeyID] objectForKey:key.keyID];
			}
			if (realKey) {
				key = realKey;
			}
		}
		
		if (i > 0) {
			seperator = normalSeperator;
			if (i == count - 1) {
				seperator = lastSeperator;
			}
		}
		
		
		BOOL isGPGKey = [key isKindOfClass:gpgKeyClass];
		
		if (isGPGKey) {
			GPGKey *primaryKey = key.primaryKey;

			NSString *name = primaryKey.name;
			NSString *email = primaryKey.email;
			NSString *keyID = [[GKFingerprintTransformer sharedInstance] transformedValue:key.fingerprint];
			
			if (name.length == 0) {
				name = email;
				email = nil;
			}
			
			if (email.length > 0) {
				if (singleKey) {
					[descriptions appendFormat:@"%@%@ <%@>%@%@", seperator, name, email, lineBreak, keyID];
				} else {
					[descriptions appendFormat:@"%@%@ <%@> (%@)", seperator, name, email, keyID];
				}
			} else {
				if (singleKey) {
					[descriptions appendFormat:@"%@%@%@%@", seperator, name, lineBreak, keyID];
				} else {
					[descriptions appendFormat:@"%@%@ (%@)", seperator, name, keyID];
				}
			}
			
		} else {
			[descriptions appendFormat:@"%@%@", seperator, [[GKFingerprintTransformer sharedInstance] transformedValue:key]];
		}
		
		
		i++;
	}
	
	return descriptions.copy;
}



+ (NSString*)searchFileForSignatureFile:(NSString*)sigFile {
    NSFileManager* fmgr = [[NSFileManager alloc] init];
    
    NSString* file = [sigFile stringByDeletingPathExtension];
    BOOL isDir = NO;
    if([fmgr fileExistsAtPath:file isDirectory:&isDir] && !isDir)
        return file;
    else
        return nil;
}

+ (NSString*)searchSignatureFileForFile:(NSString*)sigFile {
    NSFileManager* fmgr = [[NSFileManager alloc] init];
    
    NSSet* exts = [NSSet setWithObjects:@".sig", @".asc", nil];
    
    for(NSString* ext in exts) {
        NSString* file = [sigFile stringByAppendingString:ext];
        BOOL isDir = NO;
        if([fmgr fileExistsAtPath:file isDirectory:&isDir] && !isDir)
            return file;
    }
    
    return nil;
}







#pragma mark -
#pragma mark Verification result

- (NSArray<NSDictionary *> *)verificationResultsFromSigs:(NSArray<GPGSignature *> *)sigs forFile:(NSString *)file {
	NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
	
	if (sigs.count > 0) {
		// TODO: Sort the signatures from good to bad.

		for (GPGSignature *sig in sigs) {
			[results addObject:[self resultForSignature:sig file:file]];
		}
	} else {
		NSString *resultString = localized(@"No signatures found");
		if (file) {
			[results addObject:@{@"filename": file.lastPathComponent,
								 @"file": file,
								 VERIFICATION_RESULT_KEY: resultString,
								 NOTIFICATION_TITLE_KEY: resultString,
								 NOTIFICATION_MESSAGE_KEY: file.lastPathComponent}];
		} else {
			[results addObject:@{VERIFICATION_RESULT_KEY: resultString,
								 NOTIFICATION_TITLE_KEY: resultString}];
		}
	}

	return results;
}

- (NSDictionary *)resultForSignature:(GPGSignature *)sig file:(NSString *)file {
	NSMutableArray *verficationResult = [NSMutableArray new];
	NSMutableArray *notificationMessage = [NSMutableArray new];
	NSMutableArray *alertMessage = [NSMutableArray new];
	NSString *alertMessageString = nil;
	NSString *templatePrefix = nil;
	NSString *userIDDescription = nil;
	NSString *title;
	NSString *alertTitle = nil;
	BOOL signatureError = NO;
	NSString *fingerprint = nil;
	

	switch (sig.status) {
		case GPGErrorNoError:
			switch (sig.trust) {
				case GPGValidityUltimate:
					templatePrefix = @"ABSOLUTE_TRUSTED_SIGNATURE";
					break;
				case GPGValidityFull:
					templatePrefix = @"FULLY_TRUSTED_SIGNATURE";
					break;
				case GPGValidityMarginal:
					templatePrefix = @"MARGINAL_TRUSTED_SIGNATURE";
					break;
				case GPGValidityNever:
				case GPGValidityUnknown:
				case GPGValidityUndefined:
					templatePrefix = @"UNTRUSTED_SIGNATURE";
					break;
				default:
					break;
			}
			break;
		case GPGErrorCertificateRevoked:
			templatePrefix = @"REVOKED_SIGNATURE";
			break;
		case GPGErrorSignatureExpired:
		case GPGErrorKeyExpired:
			templatePrefix = @"EXPIRED_SIGNATURE";
			break;
		case GPGErrorUnknownAlgorithm:
			templatePrefix = @"UNVERIFIABLE_SIGNATURE";
			signatureError = YES;
			break;
		case GPGErrorNoPublicKey:
			templatePrefix = @"NO_PUBKEY_SIGNATURE";
			break;
		case GPGErrorBadSignature:
			templatePrefix = @"BAD_SIGNATURE";
			break;
		default:
			break;
	}
	if (!templatePrefix) {
		signatureError = YES;
		templatePrefix = @"SIGNATURE_ERROR";
	}
	
	
	if (sig.fingerprint ) {
		fingerprint = [[GPGNoBreakFingerprintTransformer sharedInstance] transformedValue:sig.fingerprint];
	}

	title = localized([templatePrefix stringByAppendingString:@"_TITLE"]);
	
	NSString *alertTitleTemplate = [templatePrefix stringByAppendingString:@"_ALERT_TITLE"];
	alertTitle = localized(alertTitleTemplate);
	if (!alertTitle || [alertTitle isEqualToString:alertTitleTemplate]) {
		alertTitle = title;
	}
	
	
	// Build userIDDescription, cut long name or email if necessary.
	if (sig.name || sig.email) {
		NSString *name = sig.name;
		NSString *email = sig.email;
		
		const NSUInteger maxLength = 60;
		// Truncate very long names and emails.
		if (name.length + email.length > maxLength) {
			NSUInteger cutLength = maxLength - 10;
			if (email.length < 30) {
				// Only truncate name.
				cutLength -= email.length;
				name = [NSString stringWithFormat:@"%@…%@", [name substringToIndex:cutLength / 2], [name substringFromIndex:name.length - cutLength / 2]];
			} else if (name.length < 30) {
				// Only truncate email.
				cutLength -= name.length;
				email = [NSString stringWithFormat:@"%@…%@", [email substringToIndex:cutLength / 2], [email substringFromIndex:email.length - cutLength / 2]];
			} else {
				// Truncate both.
				name = [NSString stringWithFormat:@"%@…%@", [name substringToIndex:cutLength / 4], [name substringFromIndex:name.length - cutLength / 4]];
				email = [NSString stringWithFormat:@"%@…%@", [email substringToIndex:cutLength / 4], [email substringFromIndex:email.length - cutLength / 4]];
			}
		}
		
		if (name.length > 0 && email.length > 0) {
			userIDDescription = [NSString stringWithFormat:@"%@ <%@>", name, email];
		} else if (name.length > 0) {
			userIDDescription = name;
		} else if (email.length > 0) {
			userIDDescription = email;
		}
	}
	
	
	
	[verficationResult addObject:alertTitle];
	
	if (signatureError) {
		NSString *errorDescription = localizedWithFormat(@"SIGNATURE_ERROR_DESCRIPTION", sig.status);
		[verficationResult addObject:errorDescription];
		[notificationMessage addObject:errorDescription];
		[alertMessage addObject:errorDescription];
	} else {
		NSString *template = [templatePrefix stringByAppendingString:@"_MESSAGE"];
		alertMessageString = localizedWithFormat(template, fingerprint);
		if ([alertMessageString isEqualToString:template]) {
			alertMessageString = nil;
		}
	}
	
	if (userIDDescription.length > 0) {
		[verficationResult addObject:userIDDescription];
		[notificationMessage addObject:userIDDescription];
		[alertMessage addObject:userIDDescription];
	}

	if (fingerprint) {
		if (sig.status != GPGErrorNoPublicKey) {
			[verficationResult addObject:fingerprint];
			[alertMessage addObject:fingerprint];
		}
		if (!file) {
			// No file verfication, so we have one more line to add the fingerprint.
			// Truncate the fingerprint so it fits into a notification.
			
			NSUInteger maxLength = 24;
			if (@available(macOS 10.14, *)) {
				if (_alertStyle == UNAlertStyleBanner) {
					maxLength = 40;
				}
			}
			
			NSString *truncatedFingerprint = fingerprint;
			if (fingerprint.length > maxLength) {
				truncatedFingerprint = [NSString stringWithFormat:@"… %@", [fingerprint substringFromIndex:fingerprint.length - maxLength]];
			}
			[notificationMessage addObject:truncatedFingerprint];
		}
	}
	
	if (file) {
		[notificationMessage addObject:file.lastPathComponent];
		[alertMessage addObject:file.lastPathComponent];
	}
	
	if (alertMessageString.length > 0) {
		if (alertMessage.count > 0) {
			[verficationResult addObject:@""];
			[alertMessage addObject:@""];
		}
		[verficationResult addObject:alertMessageString];
		[alertMessage addObject:alertMessageString];
	}

	
	NSMutableDictionary *result = [NSMutableDictionary new];
	result[VERIFICATION_RESULT_KEY] = [verficationResult componentsJoinedByString:@"\n"];
	result[NOTIFICATION_TITLE_KEY] = title;
	result[NOTIFICATION_MESSAGE_KEY] = [notificationMessage componentsJoinedByString:@"\n"];
	result[ALERT_MESSAGE_KEY] = [alertMessage componentsJoinedByString:@"\n"];
	result[ALERT_TITLE_KEY] = alertTitle;

	if (file) {
		result[@"filename"] = file.lastPathComponent;
		result[@"file"] = file;
	}
	
	
	return result.copy;
}



#pragma mark -
#pragma mark Verification operations list

- (void)setVerificationOperation:(NSDictionary *)operation forKey:(NSString *)key {
	if (!_verificationOperations) {
		// First call to this method isn't thread safe and, because of that, must be on the main thread.
		_verificationOperations = [NSMutableDictionary new];
	}
	@synchronized (_verificationOperations) {
		if (operation) {
			_verificationOperations[key] = operation;
		} else {
			[_verificationOperations removeObjectForKey:key];
		}
	}
}
- (NSDictionary *)verificationOperationForKey:(NSString *)key {
	if (!_verificationOperations) {
		// First call to this method isn't thread safe and, because of that, must be on the main thread.
		_verificationOperations = [NSMutableDictionary new];
	}
	@synchronized (_verificationOperations) {
		return _verificationOperations[key];
	}
}



#pragma mark -
#pragma mark Notifications

- (void)displaySignatureVerificationForSig:(GPGSignature *)sig {
	[self performSelectorOnMainThread:@selector(displaySignatureVerificationForSigOnMain:)
						   withObject:sig
						waitUntilDone:NO];
}
- (void)displaySignatureVerificationForSigOnMain:(GPGSignature *)sig {
	NSString *userID = sig.userIDDescription;
	NSString *validity = [[GPGValidityDescriptionTransformer new] transformedValue:@(sig.trust)];

	[self displayOperationFinishedNotificationWithTitle:localized(@"Verification successful")
												message:localizedWithFormat(@"Good signature (%@ trust):\n\"%@\"", validity, userID)];
}


- (void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body {
	void (^alertBlock)(void) = ^{
		GPGSAlert *alert = [GPGSAlert new];
		alert.messageText = title;
		alert.informativeText = body;
		[NSApp activateIgnoringOtherApps:YES];
		[alert show];
	};
	
	if ([NSThread isMainThread]) {
		alertBlock();
	} else {
		dispatch_sync(dispatch_get_main_queue(), alertBlock);
	}
}


- (void)displayOperationFinishedNotificationWithTitle:(NSString *)title message:(NSString *)body files:(NSArray *)files {
	[self performSelectorOnMainThread:@selector(displayOperationFinishedNotificationWithTitleOnMain:)
						   withObject:[NSArray arrayWithObjects:title, body, files, nil]
						waitUntilDone:NO];
}
- (void)displayOperationFinishedNotificationWithTitle:(NSString *)title message:(NSString *)body {
	[self performSelectorOnMainThread:@selector(displayOperationFinishedNotificationWithTitleOnMain:)
						   withObject:[NSArray arrayWithObjects:title, body, nil]
						waitUntilDone:NO];
}
- (void)displayOperationFinishedNotificationWithTitleOnMain:(NSArray *)args {
	NSString *title = args[0];
	NSString *body = args[1];
	NSArray *files = args.count > 2 ? args[2] : nil;

	[self displayNotificationWithTitle:title message:body files:files userInfo:nil failed:NO];
}


- (void)displayOperationFailedNotificationWithTitle:(NSString *)title message:(NSString *)body {
	[self performSelectorOnMainThread:@selector(displayOperationFailedNotificationWithTitleOnMain:)
						   withObject:[NSArray arrayWithObjects:title, body, nil]
						waitUntilDone:NO];
}
- (void)displayOperationFailedNotificationWithTitleOnMain:(NSArray *)args {
	NSString *title = args[0];
	NSString *body = args[1];

	[self displayNotificationWithTitle:title message:body files:nil userInfo:nil failed:YES];
}



- (void)displayNotificationWithTitle:(NSString *)title message:(NSString *)message files:(NSArray *)files userInfo:(NSDictionary *)userInfo failed:(BOOL)failed {
	 // the parameter "failed" is currently unused. Could be used in the future to use another sound or something.

	NSString *alertTitle = userInfo[ALERT_TITLE_KEY];
	if (alertTitle.length == 0) {
		alertTitle = title;
	}
	NSString *alertMessage = userInfo[ALERT_MESSAGE_KEY];
	if (alertMessage.length == 0) {
		alertMessage = message;
	}
	
	if (@available(macOS 10.14, *)) {
		UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
		
		content.title = title;
		content.body = message;
		content.sound = [UNNotificationSound defaultSound];
		
		NSMutableDictionary *newUserInfo = userInfo ? userInfo.mutableCopy : [NSMutableDictionary new];
		if (files.count > 0) {
			// Add the files to the userInfo and display "Show in Finder" button.
			newUserInfo[@"files"] = files.copy;
			content.categoryIdentifier = fileCategoryIdentifier;
		}
		content.userInfo = newUserInfo.copy;

		[self displayNotificationWithContent:content completionHandler:^(BOOL notificationDidShow) {
			if (!notificationDidShow) {
				// Fallback to normal dialog.
				[self displayMessageWindowWithTitleText:alertTitle bodyText:alertMessage];
			}
		}];
	} else {
		 // Fallback to normal dialog.
		 [self displayMessageWindowWithTitleText:alertTitle bodyText:alertMessage];
	 }
}

- (void)displayNotificationWithVerficationResults:(NSArray<NSDictionary *> *)results
									  fullResults:(NSArray<NSDictionary *> *)fullResults
							  operationIdentifier:(NSString *)operationIdentifier
								completionHandler:(void(^)(BOOL notificationDidShow))completionHandler {
	if (@available(macOS 10.14, *)) {
		UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
		
		NSDictionary *result = results[0];
		content.title = result[NOTIFICATION_TITLE_KEY];
		content.body = result[NOTIFICATION_MESSAGE_KEY];
		content.sound = [UNNotificationSound defaultSound];

		NSMutableDictionary *userInfo = [NSMutableDictionary new];
		userInfo[OPERATION_IDENTIFIER_KEY] = operationIdentifier;
		userInfo[ALL_VERIFICATION_RESULTS_KEY] = fullResults.copy;
		
		NSString *file = result[@"file"];
		if (file) {
			// Add the file to the userInfo and display "Show in Finder" button.
			userInfo[@"files"] = @[file];
			content.categoryIdentifier = fileCategoryIdentifier;
		}
		
		content.userInfo = userInfo.copy;

		[self displayNotificationWithContent:content completionHandler:completionHandler];
	} else {
		completionHandler(NO);
	}
}

/**
 * Displays a notification if possible.
 * @param content of the notification to show.
 * @param completionHandler gets called with a BOOL to indicate if the notificatioin was shown.
 */
- (void)displayNotificationWithContent:(UNNotificationContent *)content
					 completionHandler:(void(^)(BOOL notificationDidShow))completionHandler __OSX_AVAILABLE(10.14) {
	UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
	
	[center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
		
		if (settings.authorizationStatus == UNAuthorizationStatusDenied ||
			settings.alertStyle == UNAlertStyleNone ||
			[[[NSUserDefaults alloc] initWithSuiteName:@"com.apple.notificationcenterui"] boolForKey:@"doNotDisturb"]) {
			
			// User has disabled notifications for GPGServices or "Do not disturb" enabled.
			completionHandler(NO);
			return;
		}
		
		NSString *identifier = [NSUUID UUID].UUIDString; // A random identifier for this notificaton.
		UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:nil];
		
		[center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
			if (error) {
				completionHandler(NO);
			} else {
				completionHandler(YES);
			}
		}];
	}];
}


- (void)userNotificationCenter:(UNUserNotificationCenter *)center
	   willPresentNotification:(UNNotification *)notification
		 withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler __OSX_AVAILABLE(10.14) {
	if (@available(macOS 10.14, *)) {
		// This is required to show the notification on screen.
		completionHandler(UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionAlert);
	}
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
		 withCompletionHandler:(void(^)(void))completionHandler __OSX_AVAILABLE(10.14) {
	if (@available(macOS 10.14, *)) {
		UNNotificationContent *content = response.notification.request.content;
		NSDictionary *userInfo = content.userInfo;
		
		if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
			NSString *operationIdentifier = userInfo[OPERATION_IDENTIFIER_KEY];
			if (operationIdentifier) {
				NSDictionary *operation = [self verificationOperationForKey:operationIdentifier];
				DummyVerificationController *verificationController;
				
				if (operation) {
					// The operation is still running.
					verificationController = operation[VERIFICATION_CONTROLLER_KEY];
					NSArray *verificationResults = operation[ALL_VERIFICATION_RESULTS_KEY];
					
					if (!verificationController) {
						// Create and show a new verificaiton controller.
						verificationController = [DummyVerificationController verificationController]; // thread-safe
						[verificationController addResults:verificationResults];
						
						// Remember the new verificaiton controller.
						[self setVerificationOperation:@{VERIFICATION_CONTROLLER_KEY: verificationController,
															ALL_VERIFICATION_RESULTS_KEY: verificationResults}
												forKey:operationIdentifier];
					} else {
						// Only show the existing controller.
						[verificationController showWindow:nil];
					}
				} else {
					// No operation running. Create and show a new verification controller.
					NSArray *verificationResults = userInfo[ALL_VERIFICATION_RESULTS_KEY];
					
					verificationController = [DummyVerificationController verificationController]; // thread-safe
					[verificationController addResults:verificationResults];
				}
			} else {
				NSString *title = userInfo[ALERT_TITLE_KEY];
				if (title.length == 0) {
					title = content.title;
				}
				NSString *body = userInfo[ALERT_MESSAGE_KEY];
				if (body.length == 0) {
					body = content.body;
				}
				// Display the notification content in a dialog.
				[self displayMessageWindowWithTitleText:title bodyText:body];
			}
		} else if ([response.actionIdentifier isEqualToString:showInFinderActionIdentifier]) {
			// Show the files in Finder.
			NSArray *files = userInfo[@"files"];
			if ([files isKindOfClass:[NSArray class]] && files.count > 0) {
				NSMutableArray *urls = [NSMutableArray new];
				for (NSString *file in files) {
					[urls addObject:[NSURL fileURLWithPath:file]];
				}
				[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:urls];
			}
		}
		completionHandler();
	}
}


@end
