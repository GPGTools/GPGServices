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

- (void)awakeFromNib {
    [resultIndicatorColumn bind:@"value" 
                       toObject:arrayController
                    withKeyPath:@"arrangedObjects.color" 
                        options:nil];
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
        GPGValidity validity = [sig validity];
        NSString* validityDesc = [sig validityDescription];
        
        switch(validity) {
            case GPGValidityNever:
                bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
                break;
            case GPGValidityMarginal: 
                bgColor = [NSColor colorWithCalibratedRed:0.9 green:0.8 blue:0.0 alpha:1.0];
                break;
            case GPGValidityFull:
            case GPGValidityUltimate:
                bgColor = [NSColor colorWithCalibratedRed:0.0 green:0.8 blue:0.0 alpha:1.0];
                break;
            default:
                bgColor = [NSColor clearColor];
        }
        
        NSString* trustString = [NSString stringWithFormat:
                                 NSLocalizedString(@"(%@ trust)", @"Needed to colorize the in the results window"), 
                                 validityDesc];
        verificationResult = [NSString stringWithFormat:NSLocalizedString(@"Signed by: %@ %@",
                                                                          @"'signed by ...' verification result"), userID, trustString];                         
        NSMutableAttributedString* tmp = [[[NSMutableAttributedString alloc] initWithString:verificationResult 
                                                                                 attributes:nil] autorelease];
        NSRange range = [verificationResult rangeOfString:[NSString stringWithFormat:trustString, validityDesc]];
        [tmp addAttribute:NSFontAttributeName 
                    value:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]           
                    range:range];
        [tmp addAttribute:NSBackgroundColorAttributeName 
                    value:bgColor
                    range:range];
        
        verificationResult = (NSString*)tmp;
    } else {
        bgColor = [NSColor colorWithCalibratedRed:0.8 green:0.0 blue:0.0 alpha:0.7];
        
        NSString* failedString = NSLocalizedString(@"FAILED", @"'FAILED' translated. Needed to colorize the in the results window");
        verificationResult = [NSString stringWithFormat:NSLocalizedString(@"Verification %@: %@",
                                                                          @"'Verification FAILED ...' verification-result"),
                              failedString,
                              GPGErrorDescription([sig status])];
        NSMutableAttributedString* tmp = [[[NSMutableAttributedString alloc] initWithString:verificationResult 
                                                                                 attributes:nil] autorelease];
        NSRange range = [verificationResult rangeOfString:failedString];
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
              bgColor, @"color",
              nil];
    
    [self addResults:result];
}

@end
