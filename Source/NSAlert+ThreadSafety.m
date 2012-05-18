//
//  NSAlert+ThreadSafety.m
//  GPGServices
//
//  Created by Chris Fraire on 5/17/12.
//  Copyright (c) 2012 Chris Fraire. All rights reserved.
//

#import "NSAlert+ThreadSafety.h"

@implementation NSAlert (ThreadSafety)

// called by runModalOnMain
- (void)runModalOnMainWithResHolder:(NSMutableArray *)resHolder 
{
    NSInteger res = [self runModal];
    [resHolder addObject:[NSNumber numberWithInteger:res]];
}

- (NSInteger)runModalOnMain {
    NSMutableArray *resHolder = [NSMutableArray arrayWithCapacity:1];
    [self performSelectorOnMainThread:@selector(runModalOnMainWithResHolder:) 
                           withObject:resHolder 
                        waitUntilDone:YES];
    return [[resHolder lastObject] integerValue];
}

@end
