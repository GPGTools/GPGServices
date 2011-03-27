//
//  DirZipOperation.h
//  GPGServices
//
//  Created by Moritz Ulrich on 27.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ZKDataArchive;

@interface DirZipOperation : NSOperation {
    NSString* filePath;
    id delegate;
    
    ZKDataArchive* archive;
}

@property(retain) NSString* filePath;
@property(retain) id delegate;
@property(readonly) NSData* zipData;

@end
