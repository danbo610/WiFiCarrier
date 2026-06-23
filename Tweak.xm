#include "Tweak.h"
#include "Version.h"
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

typedef struct __WiFiNetwork *WiFiNetworkRef;
extern BOOL WiFiNetworkIsWPA(WiFiNetworkRef network);
extern BOOL WiFiNetworkIsEAP(WiFiNetworkRef network);

static NSDateFormatter *dateFormatter = nil;

static BOOL hasFullyLoaded = NO;
static BOOL bLastVPN = NO;
static BOOL bIsGettingIP = NO;

// Original values from SBTelephonyManager
static NSString *originalName = @"";
static NSString *publicIP = @"";
static id subscriptionContext = nil;
static eState eCurrentState = STATE_DISABLED;

//Reachability
//static SCNetworkReachabilityRef reachability;

// User settings
static BOOL enabled = false;
static BOOL enableDebug = false;
static BOOL enableCustomCarrier = false;
static BOOL enableSSID = false;
static BOOL enableIPADDR = false;
static BOOL enableExtIP = false;
static BOOL enableWFC = false;
BOOL enableGesture = false;
static NSString *customCarrier = @"";
static NSString *srcWiFiCalling = @"";
static NSString *customWiFiCalling1 = @"";
static NSString *customWiFiCalling2 = @"";
static NSString *gestureType = @"both";                  // longpress | doubletap | both
static NSString *publicIPURL = @"https://icanhazip.com/";


%hook STTelephonyStateProvider
//The following is for IOS 13 support.
-(void)operatorNameChanged:(id)arg1 name:(id)arg2 {
	subscriptionContext = arg1;
	originalName = arg2;
	if (!enabled || !hasFullyLoaded) {
		%orig;
		return;
	}
	%orig(arg1, GetCarrierText(arg2));
}

-(void)currentDataSimChanged:(id)arg1 {
	%orig;
	if (enabled) {
		Debug([NSString stringWithFormat:@"STTelephonyStateProvider currentDataSimChanged: '%@'", arg1]);
		publicIP = @"";
		forceUpdate();
	}
}
-(void)simStatusDidChange:(id)arg1 status:(id)arg2 {
	%orig;
	if (enabled) {
		Debug([NSString stringWithFormat:@"STTelephonyStateProvider simStatusDidChange: '%@' - '%@'", arg1, arg2]);
		publicIP = @"";
		forceUpdate();
	}
}
%end

%hook SBTelephonyManager
//The following is for IOS 12 (and 11?) support.
-(void)operatorNameChanged:(id)arg1 name:(id)arg2 {
	subscriptionContext = arg1;
	originalName = arg2;

	if (!enabled || !hasFullyLoaded) {
		%orig;
		return;
	}
	%orig(arg1, GetCarrierText(arg2));
}
-(BOOL)isUsingVPNConnection {
	BOOL bRes=%orig;
	if (enabled && bLastVPN!=bRes) {
		Debug([NSString stringWithFormat:@"SBTelephonyManager isUsingVPNConnection: %@", bRes ? @"YES" : @"NO"]);
		bLastVPN = bRes;
		publicIP=@"";
		forceUpdate();
	}
	return bRes;
}
%end

%hook SBWiFiManager
-(void)_updateCurrentNetwork {
	%orig;
	if (enabled) {
		Debug(@"SBWiFiManager _updateCurrentNetwork:");
		publicIP=@"";
		forceUpdate();
	}
}
%end

%hook NEVPNConnection
//I'm not sure this ever gets called - in theory I want it to be called when VPN connects/disconnects
-(void)setSession:(void*)arg1 {
	%orig;
	if (enabled) {
		Debug(@"NEVPNConnection setSession");
		publicIP = @"";
		forceUpdate();
	}
}
%end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
	%orig;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
		hasFullyLoaded = YES;
		forceUpdate();
	});
}
%end

%hook UIStatusBarWindow
- (id)initWithFrame:(CGRect)frame {
    self = %orig;
		[self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleGestureFrom:)]];
		UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapFrom:)];
		doubleTap.numberOfTapsRequired = 2;
		[self addGestureRecognizer:doubleTap];
	return self;
}

%new -(void)handleGestureFrom:(UILongPressGestureRecognizer *)recognizer {
	if (enableGesture && GestureAllowsLongPress() && recognizer.state == UIGestureRecognizerStateBegan) {
		ChangeState(recognizer.view);
	}
}

%new -(void)handleDoubleTapFrom:(UITapGestureRecognizer *)recognizer {
	if (enableGesture && GestureAllowsDoubleTap() && recognizer.state == UIGestureRecognizerStateRecognized) {
		ChangeState(recognizer.view);
	}
}
%end

//--------------------------------------------------//
// ===== Static functions local to this tweak ===== //

static inline NSString *StateName(eState s) {
	switch (s) {
		case STATE_SSID:          return @"WiFi SSID";
		case STATE_PUBLICIP:      return @"Public IP";
		case STATE_INTERNALIP:    return @"Internal IP";
		case STATE_CUSTOMCARRIER: return @"Custom Carrier";
		case STATE_ORIGINAL:      return @"Carrier";
		default:                  return @"Auto";
	}
}

BOOL GestureAllowsLongPress() {
	return [gestureType isEqualToString:@"longpress"] || [gestureType isEqualToString:@"both"];
}

BOOL GestureAllowsDoubleTap() {
	return [gestureType isEqualToString:@"doubletap"] || [gestureType isEqualToString:@"both"];
}

static inline void PlayHaptic() {
	UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
	[generator prepare];
	[generator impactOccurred];
}

// Brief toast naming the mode we just switched to. Hosted in its own window on the
// gesture view's scene so it shows over whatever is on screen (home screen or in-app).
static inline void ShowModeHUD(eState s, UIView *anchor) {
	NSString *text = StateName(s);
	dispatch_async(dispatch_get_main_queue(), ^{
		UIWindowScene *scene = nil;
		UIWindow *anchorWindow = [anchor isKindOfClass:[UIWindow class]] ? (UIWindow *)anchor : anchor.window;
		scene = anchorWindow.windowScene;
		if (scene == nil) {
			for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
				if ([sc isKindOfClass:[UIWindowScene class]] && sc.activationState == UISceneActivationStateForegroundActive) {
					scene = (UIWindowScene *)sc;
					break;
				}
			}
		}

		UIWindow *hudWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene]
		                            : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
		hudWindow.windowLevel = UIWindowLevelStatusBar + 100;
		hudWindow.userInteractionEnabled = NO;
		hudWindow.backgroundColor = [UIColor clearColor];
		hudWindow.hidden = NO;

		UILabel *label = [[UILabel alloc] init];
		label.text = text;
		label.textColor = [UIColor whiteColor];
		label.font = [UIFont boldSystemFontOfSize:15.0];
		label.textAlignment = NSTextAlignmentCenter;
		label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
		label.layer.cornerRadius = 12.0;
		label.clipsToBounds = YES;
		[label sizeToFit];

		CGRect wb = hudWindow.bounds;
		CGFloat w = label.bounds.size.width + 28.0;
		CGFloat h = label.bounds.size.height + 14.0;
		label.frame = CGRectMake((wb.size.width - w) / 2.0, wb.size.height * 0.16, w, h);
		[hudWindow addSubview:label];

		hudWindow.alpha = 0.0;
		[UIView animateWithDuration:0.18 animations:^{
			hudWindow.alpha = 1.0;
		} completion:^(BOOL finished) {
			[UIView animateWithDuration:0.3 delay:0.9 options:UIViewAnimationOptionCurveEaseInOut animations:^{
				hudWindow.alpha = 0.0;
			} completion:^(BOOL done) {
				hudWindow.hidden = YES;
			}];
		}];
	});
}

void ChangeState(UIView *host) {
	if (!hasFullyLoaded) return;
	if (!enableGesture) return;
	if (!enabled) {
		eCurrentState = STATE_DISABLED;
		return;
	}

	eState eStartState = eCurrentState;

	// Fixed cycle, independent of the display-option toggles (Use IP Address etc.):
	// WiFi SSID -> Public IP -> Internal IP -> Carrier (original) -> back to SSID
	switch (eCurrentState) {
		case STATE_SSID:       eCurrentState = STATE_PUBLICIP;   break;
		case STATE_PUBLICIP:   eCurrentState = STATE_INTERNALIP; break;
		case STATE_INTERNALIP: eCurrentState = STATE_ORIGINAL;   break;
		case STATE_ORIGINAL:   eCurrentState = STATE_SSID;       break;
		default:               eCurrentState = STATE_SSID;       break; // from Auto / Custom Carrier
	}

	Debug([NSString stringWithFormat:@"ChangeState from '%@' to '%@'", StateName(eStartState), StateName(eCurrentState)]);

	if (eCurrentState != eStartState) {
		PlayHaptic();
		ShowModeHUD(eCurrentState, host);
		forceUpdate();
	}
}

static inline NSString *GetCarrierText(id original) {
	NSString* newNetwork = @"";
	NSString* newCarrier = customCarrier;

	BOOL setNetwork = NO;
	NSString* networkName = GetNetworkNameOrIP(); 
	if (!IsEmpty(networkName)) {
		setNetwork = enableSSID || enableIPADDR || eCurrentState != STATE_DISABLED;
		newNetwork = networkName;
	}

	//Check for WiFi Calling and if found, append our custom WFC text
	if (enableWFC && [srcWiFiCalling length] > 0 && eCurrentState != STATE_ORIGINAL)
	{
		if ([originalName containsString:srcWiFiCalling])
		{
			if ([newNetwork length] > 0)
				newNetwork = [NSString stringWithFormat: @"%@ %@", networkName, customWiFiCalling1];
			else
				newNetwork = customWiFiCalling1;
			
			if ([newCarrier length] > 0)
				newCarrier = [NSString stringWithFormat: @"%@ %@", newCarrier, customWiFiCalling2];
			else
				newCarrier = customWiFiCalling2;
		}
	}
	
	if ([newNetwork length] == 0)
		newNetwork=[NSString stringWithFormat:@"%C", 0x200D];
	if ([newCarrier length] == 0)
		newCarrier=[NSString stringWithFormat:@"%C", 0x200D];
	
	//Generate the new carrier text and return it....
	if (setNetwork) {
		Debug([NSString stringWithFormat: @"OperatorNameChange : Was: '%@' becomes Network: '%@'", originalName, newNetwork]);
		return newNetwork;
	} else if (enableCustomCarrier) {
		Debug([NSString stringWithFormat: @"OperatorNameChange : Was: '%@' becomes Carrier: '%@'", originalName, newCarrier]);
		return newCarrier;
	}
	return original;
}

static inline void forceUpdate() {
	if (!hasFullyLoaded || subscriptionContext == nil) return;

	SBTelephonyManager *manager = [%c(SBTelephonyManager) sharedTelephonyManager];
	if (manager != nil)
	{
		if ([manager respondsToSelector:@selector(telephonyStateProvider)])
		{
			//Must be IOS13
			STTelephonyStateProvider *provider = [manager telephonyStateProvider];
			if (provider!=nil) {
				[provider operatorNameChanged:subscriptionContext name:originalName];
			} 
		} else {
			//Must be before IOS13
			[manager operatorNameChanged:subscriptionContext name:originalName];
		}
	}
	else Debug(@"Unable to grab shared open telephony manager");
	
}

//static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
//{
//	forceUpdate();
//}

// Fetch the public IP (once), gated on the configured host being reachable.
static inline void MaybeFetchPublicIP()
{
	if (bIsGettingIP || !IsEmpty(publicIP))
		return;
	bIsGettingIP = YES;
	NSString *host = [[NSURL URLWithString:publicIPURL] host];
	if (IsEmpty(host))
		host = @"icanhazip.com";
	SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, [host UTF8String]);
	if (reachability) {
		SCNetworkReachabilityFlags flags;
		bool success = SCNetworkReachabilityGetFlags(reachability, &flags);
		BOOL bAvailable = (success && (flags & kSCNetworkFlagsReachable));
		if (bAvailable)
			GetPublicIP();
		else
			bIsGettingIP = NO;
		CFRelease(reachability);
	} else {
		bIsGettingIP = NO;
	}
}

static inline NSString *GetNetworkNameOrIP()
{
	SBWiFiManager *manager = [%c(SBWiFiManager) sharedInstance];
	NSString *networkName = [manager currentNetworkName];

	switch (eCurrentState) {
		case STATE_ORIGINAL:
			publicIP = @"";
			return originalName;

		case STATE_CUSTOMCARRIER:
			publicIP = @"";
			return customCarrier;

		case STATE_SSID:
			publicIP = @"";
			return networkName;

		case STATE_INTERNALIP:
			publicIP = @"";
			return GetIPAddress();

		case STATE_PUBLICIP: {
			// Gesture-selected: always show the public IP regardless of the toggles.
			MaybeFetchPublicIP();
			NSString *ip = GetIPAddress();
			if (IsEmpty(publicIP))
				return IsEmpty(ip) ? networkName : [NSString stringWithFormat:@"🔍 %@", ip];
			return publicIP;
		}

		case STATE_DISABLED:
		default:
			// Automatic display (no gesture active), governed by the toggles.
			if (enableIPADDR) {
				if (enableExtIP) {
					MaybeFetchPublicIP();
					NSString *ip = GetIPAddress();
					if (IsEmpty(publicIP))
						return IsEmpty(ip) ? networkName : [NSString stringWithFormat:@"🔍 %@", ip];
					return publicIP;
				}
				publicIP = @"";
				return GetIPAddress();
			}
			publicIP = @"";
			return networkName;
	}
}

static inline NSString *GetIPAddress()
{
	NSString *result = nil;
	struct ifaddrs *interfaces;
	char str[INET_ADDRSTRLEN];
	if (getifaddrs(&interfaces))
		return nil;
	struct ifaddrs *test_addr = interfaces;
	while (test_addr) {
		if(test_addr->ifa_addr->sa_family == AF_INET) {
			if (strcmp(test_addr->ifa_name, "en0") == 0) {
				inet_ntop(AF_INET, &((struct sockaddr_in *)test_addr->ifa_addr)->sin_addr, str, INET_ADDRSTRLEN);
				result = [NSString stringWithUTF8String:str];
				break;
			}
		}
		test_addr = test_addr->ifa_next;
	}
	freeifaddrs(interfaces);
	return result;
}

static inline void GetPublicIP()
{
	NSURL *url = [NSURL URLWithString:publicIPURL];
	if (url == nil) {
		publicIP = @"";
		bIsGettingIP = NO;
		return;
	}
	NSURLSession *session = [NSURLSession sharedSession];
	[[session dataTaskWithURL:url
          completionHandler:^(NSData *data,
                              NSURLResponse *response,
                              NSError *error) {

			if (error==nil) {
				NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
				if (!IsEmpty(result))
					result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; // trim trailing newline/space
				publicIP = result;
				forceUpdate();
				bIsGettingIP = NO;
			}
			else {
				publicIP = @"";
				bIsGettingIP = NO;
			}
	  }] resume];
}

static inline BOOL IsEmpty(id thing) {
	return thing == nil
	|| ([thing respondsToSelector:@selector(length)]
	&& [(NSData *)thing length] == 0)
	|| ([thing respondsToSelector:@selector(count)]
	&& [(NSArray *)thing count] == 0);
}

// ===== PREFERENCE HANDLING ===== //

static void loadPrefs() {
  Debug(@"Load preferences");
  NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.highrez.wificarrier.plist"];

  if (prefs) {
    enabled = ( [prefs objectForKey:@"enabled"] ? [[prefs objectForKey:@"enabled"] boolValue] : YES );
	enableDebug = ( [prefs objectForKey:@"enableDebug"] ? [[prefs objectForKey:@"enableDebug"] boolValue] : NO );
	if (!enableDebug) {
		//delete the debug file in the tmp folder (if it exists)
		NSFileManager *fileManager = [NSFileManager defaultManager];
		if ([fileManager isDeletableFileAtPath: _DEBUGLOG_])
		{
			[fileManager removeItemAtPath:_DEBUGLOG_ error:nil];
		}
	}
	
	enableGesture = ( [prefs objectForKey:@"enableGesture"] ? [[prefs objectForKey:@"enableGesture"] boolValue] : NO );
	enableSSID = ( [prefs objectForKey:@"enableSSID"] ? [[prefs objectForKey:@"enableSSID"] boolValue] : YES );
	enableIPADDR = ( [prefs objectForKey:@"enableIPADDR"] ? [[prefs objectForKey:@"enableIPADDR"] boolValue] : NO );
	enableExtIP = ( [prefs objectForKey:@"enableExtIP"] ? [[prefs objectForKey:@"enableExtIP"] boolValue] : YES );
	enableCustomCarrier = ( [prefs objectForKey:@"enableCustomCarrier"] ? [[prefs objectForKey:@"enableCustomCarrier"] boolValue] : NO );
    customCarrier = ( [prefs objectForKey:@"customCarrier"] ? [[prefs objectForKey:@"customCarrier"] stringValue] : nil );

	enableWFC = ( [prefs objectForKey:@"detectWFC"] ? [[prefs objectForKey:@"detectWFC"] boolValue] : NO );
	srcWiFiCalling = ( [prefs objectForKey:@"srcWiFiCalling"] ? [[prefs objectForKey:@"srcWiFiCalling"] stringValue] : nil );
	customWiFiCalling1 = ( [prefs objectForKey:@"wifiCalling1"] ? [[prefs objectForKey:@"wifiCalling1"] stringValue] : nil );
	customWiFiCalling2 = ( [prefs objectForKey:@"wifiCalling2"] ? [[prefs objectForKey:@"wifiCalling2"] stringValue] : nil );

	gestureType = ( [prefs objectForKey:@"gestureType"] ? [prefs objectForKey:@"gestureType"] : @"both" );
	publicIPURL = ( ([prefs objectForKey:@"publicIPURL"] && [[prefs objectForKey:@"publicIPURL"] length] > 0) ? [prefs objectForKey:@"publicIPURL"] : @"https://icanhazip.com/" );

	Debug([NSString stringWithFormat: @"enabled: %@", enabled ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"enableGesture: %@", enableGesture ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"enableSSID: %@", enableSSID ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"enableIPADDR: %@", enableIPADDR ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"enableExtIP: %@", enableExtIP ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"enableCustomCarrier: %@", enableCustomCarrier ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"CustomCarrierText: %@", customCarrier]);
	Debug([NSString stringWithFormat: @"enableWFC: %@", enableWFC ? @"YES" : @"NO"]);
	Debug([NSString stringWithFormat: @"srcWiFiCalling: %@", srcWiFiCalling]);
	Debug([NSString stringWithFormat: @"customWiFiCalling1: %@", customWiFiCalling1]);
	Debug([NSString stringWithFormat: @"customWiFiCalling2: %@", customWiFiCalling2]);
	Debug([NSString stringWithFormat: @"gestureType: %@", gestureType]);
	Debug([NSString stringWithFormat: @"publicIPURL: %@", publicIPURL]);
  }
  else {
	Debug(@"Unable to load preferences!");
  }

}

static void refreshPrefs() {
  loadPrefs();
  publicIP = @"";
  forceUpdate();
}

static void refreshPrefs2() {
  loadPrefs();
  publicIP = @"";
  eCurrentState = STATE_DISABLED;
  forceUpdate();
}

static void initPrefs() {
  // Seed an empty preferences file on first run so loadPrefs takes its
  // default-applying branch (enabled / SSID on out of the box). We write directly
  // to the data-partition path rather than copying from the tweak bundle: the data
  // path is identical on rootless and roothide (not relocated under /var/jb or the
  // randomized jbroot), so this needs no scheme-specific path resolution.
  NSString *path = @"/var/mobile/Library/Preferences/com.highrez.wificarrier.plist";
  NSFileManager *fileManager = [NSFileManager defaultManager];
  if (![fileManager fileExistsAtPath:path]) {
    [@{} writeToFile:path atomically:YES];
  }
}

void Debug(id thing) {
	if (enableDebug && dateFormatter!=nil) {
		NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
		NSString *content = [NSString stringWithFormat:@"%@: %@\n",dateString, thing];
		
		NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:_DEBUGLOG_];
		if (fileHandle){
			[fileHandle seekToEndOfFile];
			[fileHandle writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
			[fileHandle closeFile];
		}
		else{
			[content writeToFile:_DEBUGLOG_
					  atomically:NO
						encoding:NSStringEncodingConversionAllowLossy
						   error:nil];
		}
	}
}

%ctor {
	dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	initPrefs();
	loadPrefs();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshPrefs, CFSTR("com.highrez.wificarrier/prefsupdated"), NULL, CFNotificationSuspensionBehaviorCoalesce);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshPrefs2, CFSTR("com.highrez.wificarrier/prefsupdated2"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
