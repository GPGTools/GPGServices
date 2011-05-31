//
//  GPGKey+utils.h
//  GPGServices
//
//  Created by Moritz Ulrich on 06.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Libmacgpg/Libmacgpg.h"


@interface GPGKey (GPGKey_utils)

- (GPGValidity)overallValidity;

@end
