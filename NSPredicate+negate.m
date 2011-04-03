//
//  NSPredicate+negate.m
//  GPGServices
//
//  Created by Moritz Ulrich on 03.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NSPredicate+negate.h"


@implementation NSPredicate (NSPredicate_negate)

- (NSPredicate*)negate {
    return [NSCompoundPredicate notPredicateWithSubpredicate:self];
}

@end
