//
//  GPGServices_Private.h
//  GPGServices
//
//  Created by Mento on 01.04.20.
//

#import "RecipientWindowController.h"
#import "KeyChooserWindowController.h"
#import "DummyVerificationController.h"
#import "InProgressWindowController.h"
#import "ServiceWorker.h"
#import "ServiceWorkerDelegate.h"
#import "ServiceWrappedArgs.h"
#import "GPGTempFile.h"
#import "GKFingerprintTransformer.h"
#import "SimpleTextWindow.h"
#import "GPGSAlert.h"
#import "NSArray+join.h"

#import "Libmacgpg/GPGFileStream.h"
#import "Libmacgpg/GPGMemoryStream.h"
#import <Libmacgpg/Libmacgpg.h>
#import "ZipOperation.h"
#import "ZipKit/ZKArchive.h"
#import "NSPredicate+negate.h"
#import "GPGKey+utils.h"
#import "Localization.h"
#import <UserNotifications/UserNotifications.h>

typedef enum {
    SignService,
    EncryptService,
    DecryptService,
    VerifyService,
    MyKeyService,
    MyFingerprintService,
    ImportKeyService,
} ServiceModeEnum;

typedef enum {
    SignFileService,
    EncryptFileService,
    DecryptFileService,
    VerifyFileService,
    ImportFileService,
} FileServiceModeEnum;

#define SIZE_WARNING_LEVEL_IN_MB 10


 
@interface GPGServices () <NSApplicationDelegate, ServiceWorkerDelegate, SimpleTextWindowDelegate,
						   UNUserNotificationCenterDelegate, GPGControllerDelegate>
{
	IBOutlet NSWindow *recipientWindow;
	
	NSTimer *currentTerminateTimer;
	int terminateCounter;
	
	InProgressWindowController *_inProgressCtlr;
	NSMutableDictionary *_verificationOperations;
	UNAlertStyle _alertStyle __OSX_AVAILABLE(10.14);
}



@end

