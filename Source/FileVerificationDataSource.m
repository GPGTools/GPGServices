//
//  FileVerificationDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
//#import <MacGPGME/MacGPGME.h>
#import "Libmacgpg/Libmacgpg.h"
#import "Localization.h"

#import "FileVerificationDataSource.h"

@interface FileVerificationDataSource ()

- (void)addResultsOnMain:(NSDictionary*)results;
- (void)addResultFromSigOnMain:(NSArray *)args;

@end

@implementation FileVerificationDataSource

@synthesize isActive, verificationResults;

- (id)init {
    self = [super init];
    
    verificationResults = [[NSMutableArray alloc] init];
    
    return self;
}


- (void)addResults:(NSDictionary*)results {
    [self performSelectorOnMainThread:@selector(addResultsOnMain:) withObject:results waitUntilDone:NO];
}

// called by addResults:
- (void)addResultsOnMain:(NSDictionary*)results {
    [self willChangeValueForKey:@"verificationResults"];
    [verificationResults addObject:results];
    [self didChangeValueForKey:@"verificationResults"];
}

- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file {
    [self performSelectorOnMainThread:@selector(addResultFromSigOnMain:) 
                           withObject:[NSArray arrayWithObjects:sig, file, nil] 
                        waitUntilDone:NO];
}

- (void)addResultFromSigOnMain:(NSArray *)args {
    GPGSignature *sig = [args objectAtIndex:0];
    NSString *file = [args objectAtIndex:1];
    NSDictionary* result = nil;
    
    id verificationResult = nil;
    NSColor* bgColor = nil;
    
    if([sig status] == GPGErrorNoError) {
        GPGValidity validity = sig.trust;

        switch (validity) {
            case GPGValidityNever:
                bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                break;
            case GPGValidityMarginal: 
                bgColor = [NSColor colorWithCalibratedRed:0.9 green:0.8 blue:0.0 alpha:1.0];
                break;
            case GPGValidityFull:
                bgColor = [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0];
                break;
            case GPGValidityUltimate:
                bgColor = [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0];
                break;
            default:
                bgColor = [NSColor clearColor];
				break;
       }
        
		
		NSString *formattedFingerprint = [[GPGFingerprintTransformer new] transformedValue:sig.fingerprint];
		
		NSString *string1 = localizedWithFormat(@"Signed by: %1$@ (%2$@) – ", sig.userIDDescription, formattedFingerprint);
		NSMutableAttributedString *resultString = [[NSMutableAttributedString alloc] initWithString:string1 attributes:nil];
		
		NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], NSBackgroundColorAttributeName: bgColor};
		
		NSString *validityDesc = [NSString stringWithFormat:@"%@ %@", [[GPGValidityDescriptionTransformer new] transformedValue:@(validity)], localized(@"trust")];
		NSAttributedString *trustString = [[NSAttributedString alloc] initWithString:validityDesc attributes:attributes];
		[resultString appendAttributedString:trustString];
		
		NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
		style.lineBreakMode = NSLineBreakByTruncatingMiddle;
		[resultString addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, resultString.length)];
		
		//let attributes = [NSParagraphStyleAttributeName:style]
		
		//attributedString.addAttributes(attributes, range:  range )

		
		verificationResult = resultString;
		
	} else {
        bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
        
        // Should really call GPGErrorDescription but Libmacgpg nolonger offer that.
		NSString *failed = localized(@"FAILED");
		verificationResult = localizedWithFormat(@"Verification %1$@: %2$@ (Code: %3$i)", failed, sig.humanReadableDescription, sig.status);
		
        NSMutableAttributedString* tmp = [[NSMutableAttributedString alloc] initWithString:verificationResult
                                                                                 attributes:nil];
        NSRange range = [verificationResult rangeOfString:failed];
        [tmp addAttribute:NSFontAttributeName 
                    value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                    range:range];
        [tmp addAttribute:NSBackgroundColorAttributeName 
                    value:bgColor
                    range:range];
        
        verificationResult = (NSString*)tmp;
    }
    
    
    //Add to results
    result = [NSDictionary dictionaryWithObjectsAndKeys:
              [file lastPathComponent], @"filename",
              verificationResult, @"verificationResult", 
              nil];
    
    [self addResults:result];
}

@end
