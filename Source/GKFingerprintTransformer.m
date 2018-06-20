//
//  GKFingerprintTransformer.m
//  GPGServices
//
//  Created by Mento on 20.06.18.
//

#import "GKFingerprintTransformer.h"

@implementation GKFingerprintTransformer
- (id)transformedValue:(id)value {
	NSString *transformed = [super transformedValue:value];
	transformed = [transformed stringByReplacingOccurrencesOfString:@"  " withString:@"\xC2\xA0\xC2\xA0"];
	transformed = [transformed stringByReplacingOccurrencesOfString:@" " withString:@"\xC2\xA0"];
	return transformed;
}
+ (id)sharedInstance {
	static dispatch_once_t onceToken = 0;
	__strong static id _sharedInstance = nil;
	dispatch_once(&onceToken, ^{
		_sharedInstance = [[self alloc] init];
	});
	return _sharedInstance;
}
@end

