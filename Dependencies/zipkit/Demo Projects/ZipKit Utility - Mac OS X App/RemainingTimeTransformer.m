#import "RemainingTimeTransformer.h"

@implementation RemainingTimeTransformer

+ (Class) transformedValueClass {
	return [NSString class];
}

+ (BOOL) allowsReverseTransformation {
	return NO;
}

- (id) transformedValue:(id) value {
	NSTimeInterval timeInterval = [value doubleValue];
	if (timeInterval <= 0)
		return nil;
	else if (timeInterval == NSTimeIntervalSince1970)
		return NSLocalizedString(@"Estimating time left", @"remaining time message");
	
	float s = (float)ABS(timeInterval);
	float m = s / 60.0;
	float h = m / 60.0;
	float d = h / 24.0;
	float w = d / 7.0;
	float mm = d / 30.0;

	NSUInteger seconds = roundf(s);
	NSUInteger minutes = roundf(m);
	NSUInteger hours = roundf(h);
	NSUInteger days = roundf(d);
	NSUInteger weeks = roundf(w);
	NSUInteger months = roundf(mm);

	NSString *transformedValue = NSLocalizedString(@"About a second left", @"remaining time message");
	if (weeks > 8)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u months left", @"remaining time message"), months];
	else if (days > 10)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u weeks left", @"remaining time message"), weeks];
	else if (hours > 48)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u days left", @"remaining time message"), days];
	else if (minutes > 100)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u hours left", @"remaining time message"), hours];
	else if (seconds > 100)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u minutes left", @"remaining time message"), minutes];
	else if (seconds > 50)
		transformedValue = NSLocalizedString(@"About a minute left", @"remaining time message");
	else if (seconds > 30)
		transformedValue = NSLocalizedString(@"Less than a minute left", @"remaining time message");
	else if (seconds > 1)
		transformedValue = [NSString stringWithFormat:NSLocalizedString(@"About %u seconds left", @"remaining time message"), seconds];
	
	return transformedValue;
}

@end