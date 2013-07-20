#import <Cocoa/Cocoa.h>

#import "PAListener.h"

@interface UserNotificationListener : PAListener <NSUserNotificationCenterDelegate>
{	
	NSString *title;
	NSString *subtitle;	
	NSString *informativeText;			
	NSString *activationType;
	NSString *userInfo;
	
	BOOL shouldPresentNotification;
}

- (BOOL)presentNotification;
- (void)presentNotification:(BOOL)flag;

@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSString *subtitle;
@property (nonatomic, retain) NSString *informativeText;
@property (nonatomic, retain) NSString *activationType;
@property (nonatomic, retain) NSString *userInfo;

@end
