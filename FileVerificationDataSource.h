//
//  FileVerificationDataSource.h
//  GPGServices
//
//  Created by Moritz Ulrich on 22.04.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface FileVerificationDataSource : NSObject {
    NSMutableArray* verificationResults;
}

@property(readonly) NSArray* verificationResults;

- (void)addResults:(NSDictionary*)results;

@end
