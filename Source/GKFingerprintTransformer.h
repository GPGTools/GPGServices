//
//  GKFingerprintTransformer.h
//  GPGServices
//
//  Created by Mento on 20.06.18.
//

#import <Cocoa/Cocoa.h>
#import <Libmacgpg/Libmacgpg.h>

@interface GKFingerprintTransformer : GPGFingerprintTransformer
+ (id)sharedInstance;
@end

