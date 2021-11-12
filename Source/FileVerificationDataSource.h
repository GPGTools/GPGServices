//
//  FileVerificationDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GPGSignature;

@interface FileVerificationDataSource : NSObject

@property (nonatomic, weak) IBOutlet NSWindow *window;
@property (nonatomic, readonly) NSArray<NSDictionary *> *verificationResults;

// not thread-safe
- (void)addResults:(NSArray<NSDictionary *> *)results;

@end
