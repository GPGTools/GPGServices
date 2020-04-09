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






@implementation GPGServices

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {

	[NSApp setServicesProvider:self];
	// NSUpdateDynamicServices();
	currentTerminateTimer = nil;

	_inProgressCtlr = [[InProgressWindowController alloc] init];
	
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {
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
			GPGErrorCode status = sig.status;
			GPGDebugLog(@"sig.status: %i", status);
			if ([sig status] == GPGErrorNoError) {
				[self displaySignatureVerificationForSig:sig];
			} else {
				NSString *errorMessage = nil;
				switch (status) {
					case GPGErrorBadSignature:
						errorMessage = localizedWithFormat(@"Bad signature by %@", sig.userIDDescription);
						break;
					case GPGErrorNoPublicKey:
						errorMessage = localizedWithFormat(@"Unable to verify signature! Missing public key: %@", sig.fingerprint);
						break;
					default:
						errorMessage = localizedWithFormat(@"Unexpected GPG signature status %i", status);
						break;  // I'm unsure if GPGErrorDescription should cover these signature errors
				}
				[self displayOperationFailedNotificationWithTitle:localized(@"Verification failed") message:errorMessage];
			}
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
			GPGErrorCode status = sig.status;
			GPGDebugLog(@"sig.status: %i", status);
			if ([sig status] == GPGErrorNoError) {
				[self displaySignatureVerificationForSig:sig];
			} else {
				NSString *errorMessage = nil;
				switch (status) {
					case GPGErrorBadSignature:
						errorMessage = localizedWithFormat(@"Bad signature by %@", sig.userIDDescription);
						break;
					case GPGErrorNoPublicKey:
						errorMessage = localizedWithFormat(@"Unable to verify signature! Missing public key: %@", sig.fingerprint);
						break;
					default:
						errorMessage = localizedWithFormat(@"Unexpected GPG signature status %i", status);
						break;  // I'm unsure if GPGErrorDescription should cover these signature errors
				}
				[self displayOperationFailedNotificationWithTitle:localized(@"Verification failed") message:errorMessage];
			}
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
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(signFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Signing %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Signing %u files" /*arg:count*/)];
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr showWindow:nil];
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
		NSMutableArray *signedFiles = [NSMutableArray arrayWithCapacity:[files count]];

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
		[self displayOperationFinishedNotificationWithTitle:title message:message];
	}
}

- (void)encryptFiles:(NSArray *)files {
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(encryptFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Encrypting %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Encrypting %u files" /*arg:count*/)];
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr showWindow:nil];
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

	GPGStream *gpgData = nil;
	if (dataProvider != nil) {
		gpgData = dataProvider();
	}

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
												message:[destination lastPathComponent]];
}

- (void)decryptFiles:(NSArray *)files {
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(decryptFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Decrypting %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Decrypting %u files" /*arg:count*/)];
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr showWindow:nil];
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


	NSFileManager *fmgr = [[NSFileManager alloc] init];

	NSMutableArray *decryptedFiles = [NSMutableArray arrayWithCapacity:[files count]];
	NSMutableArray<NSDictionary *> *errors = [NSMutableArray array];
	NSUInteger cancelledCount = 0;
	
	// has thread-safe methods as used here
	DummyVerificationController *dummyController = nil;

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
				GPGTempFile *tempFile = [GPGTempFile tempFileForTemplate:
										 [file stringByAppendingString:tempTemplate]
															   suffixLen:suffixLen error:&error];
				if (error) {
					[self displayOperationFailedNotificationWithTitle:
					 localized(@"Could not write to directory")
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
					[decryptedFiles addObject:file];
				}
				

				//
				// Show any signatures encountered
				//
				if (ctx.signatures.count > 0) {
					GPGDebugLog(@"found signatures: %@", ctx.signatures);

					if (dummyController == nil) {
						dummyController = [[DummyVerificationController alloc]
										   initWithWindowNibName:@"VerificationResultsWindow"];
						[dummyController showWindow:self]; // now thread-safe
						dummyController.isActive = YES; // now thread-safe
					}

					for (GPGSignature *sig in ctx.signatures) {
						[dummyController addResultFromSig:sig forFile:file];
					}
				} else if (dummyController != nil) {
					// Add a line to mention that the file isn't signed
					[dummyController addResults:[NSDictionary dictionaryWithObjectsAndKeys:
												 [file lastPathComponent], @"filename",
												 localized(@"No signatures found"), @"verificationResult",
												 nil]];
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
	
	if (innCount == 1 && outCount == 0 && errors.count == 1) {
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

	

	if (dummyController) {
		dummyController.isActive = NO;
		[dummyController performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:NO];
	} else {
		[self displayOperationFinishedNotificationWithTitle:title message:message];
	}
}

- (void)verifyFiles:(NSArray *)files {
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(verifyFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Verifying signature of %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Verifying signatures of %u files" /*arg:count*/)];
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr showWindow:nil];
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

	NSMutableSet *filesInVerification = [NSMutableSet set];
	NSFileManager *fmgr = [[NSFileManager alloc] init];

	// has thread-safe methods as used here
	DummyVerificationController *fvc = nil;

	fvc = [[DummyVerificationController alloc]
			initWithWindowNibName:@"VerificationResultsWindow"];
	[fvc showWindow:self]; // now thread-safe
	fvc.isActive = YES; // now thread-safe

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

		if (sigs != nil) {
			if (sigs.count == 0) {
				id verificationResult = nil; // NSString or NSAttributedString
				verificationResult = localized(@"Verification FAILED: No signatures found");

				NSColor *bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];

				NSRange range = [verificationResult rangeOfString:localized(@"FAILED" /*@"Matched in "Verification FAILED:"*/)];
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

				NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
										[signedFile lastPathComponent], @"filename",
										verificationResult, @"verificationResult",
										nil];
				[fvc addResults:result];
			} else if (sigs.count > 0) {
				for (GPGSignature *sig in sigs) {
					[fvc addResultFromSig:sig forFile:signedFile];
				}
			}
		} else {
			[fvc addResults:[NSDictionary dictionaryWithObjectsAndKeys:
							 [signedFile lastPathComponent], @"filename",
							 localized(@"No verifiable data found"), @"verificationResult",
							 nil]];
		}
	}

	[fvc runModal]; // thread-safe
}

// Skip fixing this for now. We need better handling of imports in libmacgpg.
/*
 * - (void)importKeyFromData:(NSData*)data {
 *  GPGController* ctx = [[[GPGController alloc] init] autorelease];
 *
 *  NSString* importText = nil;
 *  @try {
 *      importText = [ctx importFromData:data fullImport:NO];
 *  } @catch(GPGException* ex) {
 *      [self displayOperationFailedNotificationWithTitle:[ex reason]
 *                                                message:[ex description]];
 *      return;
 *  }
 *
 *  [[NSAlert alertWithMessageText:localized(@"Import result")
 *                   defaultButton:nil
 *                 alternateButton:nil
 *                     otherButton:nil
 *       informativeTextWithFormat:importText]
 *   runModal];
 * }
 */


- (void)importFiles:(NSArray *)files {
	ServiceWorker *worker = [ServiceWorker serviceWorkerWithTarget:self andAction:@selector(importFilesSync:)];

	worker.delegate = self;
	worker.workerDescription = [self describeOperationForFiles:files
												 singleFileFmt:localized(@"Importing %@" /*arg:filename*/)
												pluralFilesFmt:localized(@"Importing %u files" /*arg:count*/)];
	[_inProgressCtlr addObjectToServiceWorkerArray:worker];
	[_inProgressCtlr showWindow:nil];
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
	[self displayOperationFinishedNotificationWithTitle:title message:message];
}

#pragma mark - ServiceWorkerDelegate

- (void)workerWasCanceled:(id)worker {
	[self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)workerDidFinish:(id)worker {
	[self performSelectorOnMainThread:@selector(removeWorker:) withObject:worker waitUntilDone:YES];
}

- (void)removeWorker:(id)worker {
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
					[self goneIn60Seconds];
					return;
				}
			} else if ([pbtype isEqualToString:NSPasteboardTypeRTF]) {
				if (!(pboardString = [pboard stringForType:NSPasteboardTypeString])) {
					*error = myerror;
					[self goneIn60Seconds];
					return;
				}
			} else {
				*error = myerror;
				[self goneIn60Seconds];
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
		
		BOOL shouldExitServiceRequest = YES;
		
		if (newString != nil) {
			static NSString *const kServiceShowInWindow = @"showInWindow";
			if ([userData isEqualToString:kServiceShowInWindow]) {
				[SimpleTextWindow showText:newString withTitle:@"GPGServices" andDelegate:self];
				shouldExitServiceRequest = NO;
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
		
		if (shouldExitServiceRequest) {
			[self goneIn60Seconds];
		}
		
	} @catch (NSException *exception) {
		NSLog(@"An exception(1) occured: '%@'\nException class: %@\nBacktrace: '%@'",
			  exception.description, exception.className, exception.callStackSymbols);
		GPGDebugLog(@"Pasteboard: '%@'\nuserData: '%@'\nmode: %i", pboard, userData, mode);
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
		
		[self goneIn60Seconds];
	} @catch (NSException *exception) {
		NSLog(@"An exception(2) occured: '%@'\nException class: %@\nBacktrace: '%@'",
			  exception.description, exception.className, exception.callStackSymbols);
		GPGDebugLog(@"Pasteboard: '%@'\nuserData: '%@'\nmode: %i", pboard, userData, mode);
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

- (void)displayMessageWindowWithTitleText:(NSString *)title bodyText:(NSString *)body {
	void (^alertBlock)() = ^{
		NSAlert *alert = [NSAlert new];
		alert.messageText = title;
		alert.informativeText = body;
		
		NSWindow *window = alert.window;
		NSView *contentView = window.contentView;
		NSDictionary *views = @{@"content": contentView};
		
		// Add minimum width constraint
		NSString *format = [NSString stringWithFormat:@"[content(>=%i@999)]", 470];
		NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:format options:0 metrics:nil views:views];
		[contentView addConstraints:constraints];
		
		[NSApp activateIgnoringOtherApps:YES];
		[alert runModal];
	};
	
	if ([NSThread isMainThread]) {
		alertBlock();
	} else {
		dispatch_sync(dispatch_get_main_queue(), alertBlock);
	}
}

- (void)displayOperationFinishedNotificationWithTitle:(NSString *)title message:(NSString *)body {
	[self performSelectorOnMainThread:@selector(displayOperationFinishedNotificationWithTitleOnMain:)
						   withObject:[NSArray arrayWithObjects:title, body, nil]
						waitUntilDone:NO];
}

// called by displayOperationFinishedNotificationWithTitle:message:
- (void)displayOperationFinishedNotificationWithTitleOnMain:(NSArray *)args {
	NSString *title = [args objectAtIndex:0];
	NSString *body = [args objectAtIndex:1];

	[self displayMessageWindowWithTitleText:title bodyText:body];
}

- (void)displayOperationFailedNotificationWithTitle:(NSString *)title message:(NSString *)body {
	[self performSelectorOnMainThread:@selector(displayOperationFailedNotificationWithTitleOnMain:)
						   withObject:[NSArray arrayWithObjects:title, body, nil]
						waitUntilDone:NO];
}

// called by displayOperationFailedNotificationWithTitle:message:
- (void)displayOperationFailedNotificationWithTitleOnMain:(NSArray *)args {
	NSString *title = [args objectAtIndex:0];
	NSString *body = [args objectAtIndex:1];

	[self displayMessageWindowWithTitleText:title bodyText:body];
}

- (void)displaySignatureVerificationForSig:(GPGSignature *)sig {
	[self performSelectorOnMainThread:@selector(displaySignatureVerificationForSigOnMain:)
						   withObject:sig
						waitUntilDone:NO];
}

// called by displaySignatureVerificationForSig:
- (void)displaySignatureVerificationForSigOnMain:(GPGSignature *)sig {
	/*
	 * GPGContext* aContext = [[[GPGContext alloc] init] autorelease];
	 * NSString* userID = [[aContext keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
	 * NSString* validity = [sig validityDescription];
	 */

	NSString *userID = sig.userIDDescription;
	NSString *validity = [[GPGValidityDescriptionTransformer new] transformedValue:@(sig.trust)];

	NSAlert *alert = [NSAlert new];
	alert.messageText = localized(@"Verification successful");
	alert.informativeText = localizedWithFormat(@"Good signature (%@ trust):\n\"%@\"", validity, userID);
	
	[NSApp activateIgnoringOtherApps:YES];
	[alert runModal];
}


- (IBAction)closeModalWindow:(id)sender {
	[NSApp stopModalWithCode:[sender tag]];
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
		currentTerminateTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(selfQuit:) userInfo:nil repeats:YES];
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






@end
