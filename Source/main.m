//
//  main.m
//  GPGServices
//
//  Created by Robert Goldsmith on 24/06/2006.
//  Copyright __MyCompanyName__ 2006. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Libmacgpg/Libmacgpg.h>
#import "GPGServices.h"

#define localized(key) [GPGServices localizedStringForKey:(key)]

int main(int argc, char *argv[]) {
	if (![GPGController class]) {
		NSRunAlertPanel(localized(@"LIBMACGPG_NOT_FOUND_TITLE"), localized(@"LIBMACGPG_NOT_FOUND_MESSAGE"), nil, nil, nil);
		return 1;
	}
#ifdef CODE_SIGN_CHECK
	/* Check the validity of the code signature. */
	NSBundle *bundle = [NSBundle mainBundle];
    if (![bundle respondsToSelector:@selector(isValidSigned)] || !bundle.isValidSigned) {
		NSRunAlertPanel(localized(@"CODE_SIGN_ERROR_TITLE"), localized(@"CODE_SIGN_ERROR_MESSAGE"), nil, nil, nil);
        return 1;
    }
#endif
    return NSApplicationMain(argc,  (const char **) argv);
}
