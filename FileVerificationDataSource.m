//
//  FileVerificationDataSource.m
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
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
    NSColor* bgColor = nil;
    
    if(GPGErrorCodeFromError([sig status]) == GPGErrorNoError) {
        GPGContext* ctx = [[[GPGContext alloc] init] autorelease];
        NSString* userID = [[ctx keyFromFingerprint:[sig fingerprint] secretKey:NO] userID];
        NSString* validity = [sig validityDescription];
        
        verificationResult = [NSString stringWithFormat:@"Signed by: %@ (%@ trust)", userID, validity];                         
        NSMutableAttributedString* tmp = [[[NSMutableAttributedString alloc] initWithString:verificationResult 
                                                                                 attributes:nil] autorelease];
        NSRange range = [verificationResult rangeOfString:[NSString stringWithFormat:@"(%@ trust)", validity]];
        [tmp addAttribute:NSFontAttributeName 
                    value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                    range:range];
        [tmp addAttribute:NSBackgroundColorAttributeName 
                    value:[NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0]
                    range:range];
        
        verificationResult = (NSString*)tmp;
        
        bgColor = [NSColor greenColor];
    } else {
        verificationResult = [NSString stringWithFormat:@"Verification FAILED: %@", GPGErrorDescription([sig status])];
        NSMutableAttributedString* tmp = [[[NSMutableAttributedString alloc] initWithString:verificationResult 
                                                                                 attributes:nil] autorelease];
        NSRange range = [verificationResult rangeOfString:@"FAILED"];
        [tmp addAttribute:NSFontAttributeName 
                    value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                    range:range];
        [tmp addAttribute:NSBackgroundColorAttributeName 
                    value:[NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7]
                    range:range];
        
        verificationResult = (NSString*)tmp;
        bgColor = [NSColor redColor];
    }
    
    
    //Add to results
    result = [NSDictionary dictionaryWithObjectsAndKeys:
              [file lastPathComponent], @"filename",
              verificationResult, @"verificationResult", 
              [NSNumber numberWithBool:YES], @"verificationSucceeded",
              bgColor, @"bgColor",
              nil];
    
    [self addResults:result];
}

@end
