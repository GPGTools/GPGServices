//
//  FileVerificationDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GPGSignature;

@interface FileVerificationDataSource : NSObject {
    NSMutableArray* verificationResults;
    BOOL isActive;
}

@property(readonly) NSArray* verificationResults;
@property(assign) BOOL isActive;

// thread-safe
- (void)addResults:(NSDictionary*)results;
// thread-safe
- (void)addResultFromSig:(GPGSignature*)sig forFile:(NSString*)file;

@end
