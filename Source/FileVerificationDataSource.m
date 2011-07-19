//
//  FileVerificationDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <MacGPGME/MacGPGME.h>

#import "FileVerificationDataSource.h"

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
    [self willChangeValueForKey:@"verificationResults"];
    [verificationResults addObject:results];
    [self didChangeValueForKey:@"verificationResults"];
}

- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file {
    NSDictionary* result = nil;
    
    id verificationResult = nil;
    NSImage* indicatorImage = nil;

    if(GPGErrorCodeFromError([sig status]) == GPGErrorNoError) {
        GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
        NSString* userID = [[ctx keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
        GPGValidity validity = [sig validity];
        NSString* validityDesc = [sig validityDescription];
        
        switch(validity) {
            case GPGValidityNever:
            case GPGValidityUndefined:
            case GPGValidityUnknown:
                indicatorImage = [NSImage imageNamed:@"redmaterial"];
                break;
            case GPGValidityMarginal: 
                indicatorImage = [NSImage imageNamed:@"yellowmaterial"];
                break;
            case GPGValidityFull:
            case GPGValidityUltimate:
                indicatorImage = [NSImage imageNamed:@"greenmaterial"];
                break;
            default:
                indicatorImage = [NSImage imageNamed:@"aquamaterial"];
        }
        
        verificationResult = [NSString stringWithFormat:NSLocalizedString(@"Signed by: %@ (%@ trust)", @"signer name and trust"), 
                              userID, validityDesc];
    } else {
        indicatorImage = [NSImage imageNamed:@"redmaterial"];
        
        verificationResult = [NSString stringWithFormat:NSLocalizedString(@"Verification FAILED: %@", @"Verification failed message"),
                              GPGErrorDescription([sig status])];
    }
    
    //Add to results
    result = [NSDictionary dictionaryWithObjectsAndKeys:
              [file lastPathComponent], @"filename",
              verificationResult, @"verificationResult", 
              indicatorImage, @"indicatorImage",
              nil];
    
    [self addResults:result];
}

@end
