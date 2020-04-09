//
//  Localization.m
//  GPGServices
//
//  Created by Mento on 28.01.19.
//

#import "Localization.h"


NSString *localized(NSString *key) {
	if (!key) {
		return nil;
	}
	static NSBundle *bundle = nil, *englishBundle = nil;
	if (!bundle) {
		bundle = [NSBundle mainBundle];
		englishBundle = [NSBundle bundleWithPath:[bundle pathForResource:@"en" ofType:@"lproj"]];
	}
	
	NSString *notFoundValue = @"~#*?*#~";
	NSString *localized = [bundle localizedStringForKey:key value:notFoundValue table:nil];
	if (localized == notFoundValue) {
		localized = [englishBundle localizedStringForKey:key value:nil table:nil];
	}
	
	return localized;
}

NSString *localizedWithFormat(NSString *key, ...) {
	va_list args;
	va_start(args, key);
	
	NSString *format = localized(key);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	
	return message;
}
