#import "listener.h"

@implementation UserNotificationListener

@synthesize title;
@synthesize subtitle;
@synthesize informativeText;
@synthesize activationType;
@synthesize userInfo;

- (void)retainNotificationInfo:(NSUserNotification *)notification
{
	self.title = notification.title;
	self.subtitle = notification.subtitle;
	self.informativeText = notification.informativeText;
	
	if(notification.userInfo){
		self.userInfo = PA_createStringFromDictionary(notification.userInfo);
	}else{
		self.userInfo = @"";	
	}
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
	if([self lock]){
		
		[self retainNotificationInfo:notification];
		
		self.activationType = @"";
		
		self.notificationType = @"DeliverNotification";	
		
		PA_UnfreezeProcess([self.listenerProcessNumber intValue]);	
	}

}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	if([self lock]){
	
		[self retainNotificationInfo:notification];

		switch(notification.activationType){
			case NSUserNotificationActivationTypeNone:
				self.activationType = @"ActivationTypeNone";				
				break;
			case NSUserNotificationActivationTypeContentsClicked:				
				self.activationType = @"ContentsClicked";				
				break;	
			case NSUserNotificationActivationTypeActionButtonClicked:				
				self.activationType = @"ActionButtonClicked";				
				break;		
			default:
				self.activationType = @"";
				break;
		}
				
		self.notificationType = @"ActivateNotification";
		
		PA_UnfreezeProcess([self.listenerProcessNumber intValue]);
		
	}
	
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return shouldPresentNotification;
}

- (BOOL)presentNotification
{
	return shouldPresentNotification;
}

- (void)presentNotification:(BOOL)flag
{
	shouldPresentNotification = flag;
}

@end