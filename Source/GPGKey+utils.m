//
//  GPGKey+utils.m
//  GPGServices
//
//  Created by Moritz Ulrich on 06.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "GPGKey+utils.h"

@implementation GPGKey (GPGKey_utils)

+ (NSString*)validityDescription:(GPGValidity)validity {
    switch(validity) {
        case GPGValidityUndefined:
            return @"Undefined";
        case GPGValidityNever:
            return @"Never";
        case GPGValidityMarginal:
            return @"Marginal";
        case GPGValidityFull:
            return @"Full";
        case GPGValidityUltimate:
            return @"Ultimate";
        default:
            return @"Unknown";
    }
    
    return @"Unknown";
}

- (GPGValidity)overallValidity {
    GPGValidity val = [self validity];
    
    //Simply return the highest trust
    for(GPGUserID *uid in [self userIDs])
        if([uid validity] > val)
            val = [uid validity];
    
    return val;
}

- (NSString*)algorithmDescription {
    /*
     typedef enum {
     GPG_RSAAlgorithm                =  1,
     GPG_RSAEncryptOnlyAlgorithm     =  2,
     GPG_RSASignOnlyAlgorithm        =  3,
     GPG_ElgamalEncryptOnlyAlgorithm = 16,
     GPG_DSAAlgorithm                = 17,
     GPG_EllipticCurveAlgorithm      = 18,
     GPG_ECDSAAlgorithm              = 19,
     GPG_ElgamalAlgorithm            = 20,
     GPG_DiffieHellmanAlgorithm      = 21
     } GPGPublicKeyAlgorithm;
     */
    
    switch([self algorithm]) {
        case GPG_RSAAlgorithm: return @"RSA";
        case GPG_RSAEncryptOnlyAlgorithm: return @"RSA-E";
        case GPG_RSASignOnlyAlgorithm: return @"RSA-S";
        case GPG_ElgamalEncryptOnlyAlgorithm: return @"ELG-E";
        case GPG_DSAAlgorithm: return @"DSA";
        case GPG_EllipticCurveAlgorithm: return @"EllipticCurve";
        case GPG_ECDSAAlgorithm: return @"ECDSAA";
        case GPG_ElgamalAlgorithm: return @"ELG";
        case GPG_DiffieHellmanAlgorithm: return @"DH";
        default: return @"Unknown";
    }
}


@end
