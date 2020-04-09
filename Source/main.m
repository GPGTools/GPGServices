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
#import "Localization.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (![GPGController class]) {
			NSAlert *alert = [NSAlert new];
			alert.messageText = localized(@"LIBMACGPG_NOT_FOUND_TITLE");
			alert.informativeText = localized(@"LIBMACGPG_NOT_FOUND_MESSAGE");
			[alert runModal];
            return 1;
        }
#ifdef CODE_SIGN_CHECK
        /* Check the validity of the code signature. */
        NSBundle *bundle = [NSBundle mainBundle];
        if (![bundle respondsToSelector:@selector(isValidSigned)] || !bundle.isValidSigned) {
			NSAlert *alert = [NSAlert new];
			alert.messageText = localized(@"CODE_SIGN_ERROR_TITLE");
			alert.informativeText = localized(@"CODE_SIGN_ERROR_MESSAGE");
			[alert runModal];
            return 1;
        }
#endif
    }
    
    return NSApplicationMain(argc,  (const char **) argv);
}
