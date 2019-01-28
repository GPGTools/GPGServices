//
//  GPGKey+utils.m
//  GPGServices
//
//  Created by Moritz Ulrich on 06.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "GPGKey+utils.h"

@implementation GPGKey (GPGKey_utils)

- (GPGValidity)overallValidity {
    GPGValidity val = [self validity];
    
    // S̶i̶m̶p̶l̶̵y̶ return the highest trust.
    for (GPGUserID *uid in [self userIDs]) {
		GPGValidity uidVal = uid.validity;
		if (uidVal < 8) { /* < 8 means valid */
			if (uidVal > val || val >= 8) { /* Higher validity than val or val isn't valid */
				val = uidVal;
			}
		} else if (val >= 8) {
			if ((uidVal & 7) > (val & 7)) { /* Higher validity than val */
				val = uidVal;
			} else if ((uidVal & 7) == (val & 7) && uidVal < val) { /* val is more invalid */
				val = uidVal;
			}
		}
	}
    
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
        case GPG_ECDHAlgorithm: return @"ECDH";
        case GPG_ECDSAAlgorithm: return @"ECDSAA";
        case GPG_ElgamalAlgorithm: return @"ELG";
        case GPG_DiffieHellmanAlgorithm: return @"DH";
        default: return @"Unknown";
    }
}


@end
