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
    
    //Simply return the highest trust
    for(GPGSubkey* uid in [self userIDs])
        if([uid validity] > val)
            val = [uid validity];
    
    return val;
}

@end
