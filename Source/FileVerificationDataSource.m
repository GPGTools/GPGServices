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

- (void)dealloc {
    [verificationResults release];
    [super dealloc];
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
        GPGValidity validity = [sig trust]; 
        NSString* validityDesc = nil;
        // We should have a validity description method, like [sig validityDescription]

        switch(validity) {
            case GPGValidityUnknown:
                bgColor = [NSColor clearColor];
                validityDesc = @"unknown";
                break;
            case GPGValidityUndefined:
                bgColor = [NSColor clearColor];
                validityDesc = @"undefined";
                break;
            case GPGValidityNever:
                bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                validityDesc = @"never";
                break;
            case GPGValidityMarginal: 
                bgColor = [NSColor colorWithCalibratedRed:0.9 green:0.8 blue:0.0 alpha:1.0];
                validityDesc = @"marginal";
                break;
            case GPGValidityFull:
                bgColor = [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0];
                validityDesc = @"full";
                break;
            case GPGValidityUltimate:
                bgColor = [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0];
                validityDesc = @"ultimate";
                break;
            default:
                bgColor = [NSColor clearColor];
        }
        
		
		NSString *string1 = [NSString stringWithFormat:@"Signed by: %@ (%@) – ", sig.userIDDescription, sig.fingerprint.shortKeyID];
		NSMutableAttributedString *resultString = [[[NSMutableAttributedString alloc] initWithString:string1 attributes:nil] autorelease];
		
		NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]], NSBackgroundColorAttributeName: bgColor};
		NSAttributedString *trustString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ trust", validityDesc] attributes:attributes];
		[resultString appendAttributedString:trustString];
		[trustString release];
		
		
		verificationResult = resultString;
		
	} else {
        bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
        
        // Should really call GPGErrorDescription but Libmacgpg nolonger offer that.
        verificationResult = [NSString stringWithFormat:@"Verification FAILED: %d", [sig status]];
        NSMutableAttributedString* tmp = [[[NSMutableAttributedString alloc] initWithString:verificationResult 
                                                                                 attributes:nil] autorelease];
        NSRange range = [verificationResult rangeOfString:@"FAILED"];
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
