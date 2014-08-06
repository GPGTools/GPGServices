//
//  DirZipOperation.h
//  GPGServices
//
//  Created by Moritz Ulrich on 27.03.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ZKDataArchive;

@interface ZipOperation : NSOperation {
    NSString* filePath;
    NSArray* files;
    id delegate;
    
    ZKDataArchive* archive;
}

@property(strong) NSString* filePath;
@property(strong) NSArray* files;
@property(strong) id delegate;
@property(readonly) NSData* zipData;

@end
