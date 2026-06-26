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

// Per-slot capture (dual-SIM): each slot's last context + name.
static id subscriptionContext1 = nil;   // SIM 1
static id subscriptionContext2 = nil;   // SIM 2
static NSString *originalName1 = @"";
static NSString *originalName2 = @"";

// Per-slot configuration (index 1 = SIM 1, 2 = SIM 2). loadPrefs fills these from the
// per-SIM preference keys (e.g. enableSSID_1 / enableSSID_2); GetCarrierTextForSlot
// "pages" the chosen slot's config into the working globals and reuses GetCarrierText.
static BOOL gEnableSSID[3], gEnableIPADDR[3], gEnableExtIP[3], gEnableCustom[3], gEnableWFC[3];
static NSString *gCustomCarrier[3], *gSrcWFC[3], *gWFC1[3], *gWFC2[3], *gPublicIPURL[3];
static eState gState[3];   // per-slot gesture cycle position (STATE_DISABLED = follow toggles)
static NSString *gLastPublished[3];   // last carrier name written to the carriers file

// Last status-bar touch location, captured in hitTest: — a UITapGestureRecognizer's
// locationInView: returns 0 once the taps lift, so we can't rely on it for left/right.
static CGFloat gLastTouchX = -1.0;
static CGFloat gLastTouchW = 0.0;

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
static NSString *publicIPURL = @"https://ipv4.icanhazip.com/"; // scratch (paged-in per slot)


%hook STTelephonyStateProvider
//The following is for IOS 13 support.
-(void)operatorNameChanged:(id)arg1 name:(id)arg2 {
	int slot = SlotForContext(arg1);
	if (slot == 1)      { subscriptionContext1 = arg1; originalName1 = arg2; }
	else if (slot == 2) { subscriptionContext2 = arg1; originalName2 = arg2; }
	subscriptionContext = arg1;
	originalName = arg2;
	PublishCarrierName(slot, arg2);

	Debug([NSString stringWithFormat:@"operatorNameChanged slot=%d name='%@'", slot, arg2]);

	if (!enabled || !hasFullyLoaded) {
		%orig;
		return;
	}
	%orig(arg1, GetCarrierTextForSlot(slot, arg2));
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
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	if (event != nil) {   // a real touch — remember where it landed for the gesture handlers
		gLastTouchX = point.x;
		gLastTouchW = self.bounds.size.width;
	}
	return %orig;
}

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
		ChangeStateForSlot(SlotForGesture(recognizer), recognizer.view);
	}
}

%new -(void)handleDoubleTapFrom:(UITapGestureRecognizer *)recognizer {
	if (enableGesture && GestureAllowsDoubleTap() && recognizer.state == UIGestureRecognizerStateRecognized) {
		ChangeStateForSlot(SlotForGesture(recognizer), recognizer.view);
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
static inline void ShowModeHUD(NSString *text, UIView *anchor) {
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

// Left half of the status bar = SIM 1 (主卡), right half = SIM 2 (副卡).
int SlotForGesture(UIGestureRecognizer *recognizer) {
	// Prefer the touch X captured in hitTest: (reliable for both long-press and the
	// double-tap, whose own locationInView: reads 0 after the taps lift). Fall back
	// to the recognizer's own location if no touch was captured.
	CGFloat x = gLastTouchX, w = gLastTouchW;
	if (x < 0 || w <= 0) {
		UIView *v = recognizer.view;
		x = [recognizer locationInView:v].x;
		w = v.bounds.size.width;
	}
	int slot = (w > 0 && x >= w / 2.0) ? 2 : 1;
	Debug([NSString stringWithFormat:@"SlotForGesture %@ x=%.1f w=%.1f -> SIM %d", [recognizer class], x, w, slot]);
	return slot;
}

// Advance one SIM one step along the cycle, starting from its CURRENT position
// (state is tracked per slot and persists, so this never resets to the start):
//   WiFi SSID -> Public IP -> Internal IP -> Carrier(original) -> back to SSID.
void ChangeStateForSlot(int slot, UIView *host) {
	if (!hasFullyLoaded || !enableGesture || !enabled) return;
	if (slot != 1 && slot != 2) return;

	eState start = gState[slot];
	eState next;
	switch (start) {
		case STATE_SSID:       next = STATE_PUBLICIP;   break;
		case STATE_PUBLICIP:   next = STATE_INTERNALIP; break;
		case STATE_INTERNALIP: next = STATE_ORIGINAL;   break;
		case STATE_ORIGINAL:   next = STATE_SSID;       break;
		default:               next = STATE_SSID;       break; // from toggle-driven -> enter at SSID
	}
	gState[slot] = next;

	Debug([NSString stringWithFormat:@"ChangeState SIM %d from '%@' to '%@'", slot, StateName(start), StateName(next)]);

	PlayHaptic();
	ShowModeHUD([NSString stringWithFormat:@"SIM %d: %@", slot, StateName(next)], host);
	forceUpdate();
}

// Which physical SIM slot does this call belong to? (1, 2, or 0=unknown)
// arg1 is a CTXPCServiceSubscriptionContext whose description carries
// slotID=CTSubscriptionSlotOne / CTSubscriptionSlotTwo — the authoritative,
// stable per-slot identifier (verified on-device).
static inline int SlotForContext(id ctx) {
	if (ctx == nil) return 0;
	NSString *desc = [ctx description];
	if (![desc isKindOfClass:[NSString class]]) return 0;
	if ([desc rangeOfString:@"SlotOne"].location != NSNotFound) return 1;
	if ([desc rangeOfString:@"SlotTwo"].location != NSNotFound) return 2;
	return 0;
}

// Publish a slot's carrier name to a small file the Settings bundle reads to label
// the SIM tabs (e.g. "SIM 1 · 中国移动"). Only written when the name actually changes.
static inline void PublishCarrierName(int slot, id name) {
	if ((slot != 1 && slot != 2) || ![name isKindOfClass:[NSString class]] || [name length] == 0) return;
	if ([name isEqualToString:gLastPublished[slot]]) return;
	gLastPublished[slot] = name;
	NSString *path = @"/var/mobile/Library/Preferences/com.highrez.wificarrier.carriers.plist";
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path];
	if (!d) d = [NSMutableDictionary dictionary];
	d[[NSString stringWithFormat:@"%d", slot]] = name;
	[d writeToFile:path atomically:YES];
}

// Per-slot carrier text: page the slot's saved config into the working globals and
// reuse the existing single-display logic. eCurrentState (paged from gState[slot]):
// STATE_DISABLED = follow the toggles; a gesture state overrides at runtime.

// The status-bar carrier text silently drops any string containing ':' (verified
// on-device — IPv4's dots and even very long text marquee-scroll fine, but a colon
// blanks it). So replace colons with dots, e.g. a public IPv6
// 2409:895b:…:ff72 -> 2409.895b.….ff72. No truncation — length is fine.
static inline NSString *SanitizeForStatusBar(NSString *s) {
	if (![s isKindOfClass:[NSString class]] || ![s containsString:@":"]) return s;
	return [s stringByReplacingOccurrencesOfString:@":" withString:@"."];
}

static inline NSString *GetCarrierTextForSlot(int slot, id original) {
	if (slot != 1 && slot != 2) return original;
	enableSSID          = gEnableSSID[slot];
	enableIPADDR        = gEnableIPADDR[slot];
	enableExtIP         = gEnableExtIP[slot];
	enableCustomCarrier = gEnableCustom[slot];
	customCarrier       = gCustomCarrier[slot];
	enableWFC           = gEnableWFC[slot];
	srcWiFiCalling      = gSrcWFC[slot];
	customWiFiCalling1  = gWFC1[slot];
	customWiFiCalling2  = gWFC2[slot];
	publicIPURL         = gPublicIPURL[slot] ?: @"https://ipv4.icanhazip.com/";
	eCurrentState       = gState[slot];
	NSString *result = SanitizeForStatusBar(GetCarrierText(original));
	Debug([NSString stringWithFormat:@"slot %d set '%@'", slot, result]);   // async, light
	return result;
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
	if (!hasFullyLoaded) return;

	SBTelephonyManager *manager = [%c(SBTelephonyManager) sharedTelephonyManager];
	if (manager != nil)
	{
		if ([manager respondsToSelector:@selector(telephonyStateProvider)])
		{
			//Must be IOS13+
			STTelephonyStateProvider *provider = [manager telephonyStateProvider];
			if (provider != nil) {
				// Replay each captured slot so both SIMs are refreshed independently.
				if (subscriptionContext1 != nil) [provider operatorNameChanged:subscriptionContext1 name:originalName1];
				if (subscriptionContext2 != nil) [provider operatorNameChanged:subscriptionContext2 name:originalName2];
				if (subscriptionContext1 == nil && subscriptionContext2 == nil && subscriptionContext != nil)
					[provider operatorNameChanged:subscriptionContext name:originalName];
			}
		} else {
			//Must be before IOS13
			if (subscriptionContext != nil)
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
		host = @"ipv4.icanhazip.com";
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

	// NOTE: do not clear `publicIP` here. It is a shared cache and both SIMs are
	// rendered per forceUpdate; a SIM that isn't showing Public IP must not wipe the
	// cache the other SIM needs. The cache is invalidated by the network/SIM/VPN/prefs
	// change handlers instead.
	switch (eCurrentState) {
		case STATE_ORIGINAL:
			return originalName;

		case STATE_CUSTOMCARRIER:
			return customCarrier;

		case STATE_SSID:
			return networkName;

		case STATE_INTERNALIP:
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
				return GetIPAddress();
			}
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

// Read a per-SIM key (e.g. "enableSSID" + slot -> "enableSSID_1").
static inline BOOL PrefBool(NSDictionary *prefs, NSString *base, int slot, BOOL def) {
	id v = [prefs objectForKey:[NSString stringWithFormat:@"%@_%d", base, slot]];
	return v ? [v boolValue] : def;
}
static inline NSString *PrefStr(NSDictionary *prefs, NSString *base, int slot, NSString *def) {
	id v = [prefs objectForKey:[NSString stringWithFormat:@"%@_%d", base, slot]];
	return [v isKindOfClass:[NSString class]] ? (NSString *)v : def;
}

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
	// Per-SIM display config (keys are suffixed _1 / _2; defaults match the old globals).
	for (int s = 1; s <= 2; s++) {
		gEnableSSID[s]    = PrefBool(prefs, @"enableSSID", s, YES);
		gEnableIPADDR[s]  = PrefBool(prefs, @"enableIPADDR", s, NO);
		gEnableExtIP[s]   = PrefBool(prefs, @"enableExtIP", s, YES);
		gEnableCustom[s]  = PrefBool(prefs, @"enableCustomCarrier", s, NO);
		gEnableWFC[s]     = PrefBool(prefs, @"detectWFC", s, NO);
		gCustomCarrier[s] = PrefStr(prefs, @"customCarrier", s, @"");
		gSrcWFC[s]        = PrefStr(prefs, @"srcWiFiCalling", s, @"");
		gWFC1[s]          = PrefStr(prefs, @"wifiCalling1", s, @"");
		gWFC2[s]          = PrefStr(prefs, @"wifiCalling2", s, @"");
		NSString *url     = PrefStr(prefs, @"publicIPURL", s, @"https://ipv4.icanhazip.com/");
		gPublicIPURL[s]   = [url length] ? url : @"https://ipv4.icanhazip.com/";
		Debug([NSString stringWithFormat:@"SIM %d: SSID=%d IP=%d ExtIP=%d Custom=%d('%@') WFC=%d state=%d url=%@",
			s, gEnableSSID[s], gEnableIPADDR[s], gEnableExtIP[s], gEnableCustom[s], gCustomCarrier[s], gEnableWFC[s], (int)gState[s], gPublicIPURL[s]]);
	}

	// gestureType is stored as a string ("longpress"/"doubletap"/"both"); accept a
	// numeric index too in case the segmented cell ever stores one.
	id gt = [prefs objectForKey:@"gestureType"];
	if ([gt isKindOfClass:[NSString class]] && [(NSString *)gt length] > 0) {
		gestureType = gt;
	} else if ([gt isKindOfClass:[NSNumber class]]) {
		int gi = [gt intValue];
		gestureType = (gi == 0) ? @"longpress" : (gi == 1) ? @"doubletap" : @"both";
	} else {
		gestureType = @"both";
	}
	Debug([NSString stringWithFormat: @"enabled: %@ enableGesture: %@ gestureType: %@", enabled ? @"YES" : @"NO", enableGesture ? @"YES" : @"NO", gestureType]);
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
  gState[1] = STATE_DISABLED;   // back to toggle-driven for both SIMs
  gState[2] = STATE_DISABLED;
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
	if (!enableDebug || dateFormatter == nil) return;
	NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
	NSString *content = [NSString stringWithFormat:@"%@: %@\n", dateString, thing];

	// Write off the main thread: this runs inside operatorNameChanged etc., and blocking
	// the main thread on file I/O here starves the status bar (it dropped the 5G/signal
	// indicator under heavy logging). A serial queue keeps lines ordered.
	static dispatch_queue_t logQueue;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		logQueue = dispatch_queue_create("com.highrez.wificarrier.log", DISPATCH_QUEUE_SERIAL);
	});
	dispatch_async(logQueue, ^{
		NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:_DEBUGLOG_];
		if (fileHandle) {
			[fileHandle seekToEndOfFile];
			[fileHandle writeData:[content dataUsingEncoding:NSUTF8StringEncoding]];
			[fileHandle closeFile];
		} else {
			[content writeToFile:_DEBUGLOG_ atomically:NO encoding:NSStringEncodingConversionAllowLossy error:nil];
		}
	});
}

%ctor {
	dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
	gState[1] = STATE_DISABLED;   // both SIMs start toggle-driven (no gesture yet)
	gState[2] = STATE_DISABLED;
	initPrefs();
	loadPrefs();
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshPrefs, CFSTR("com.highrez.wificarrier/prefsupdated"), NULL, CFNotificationSuspensionBehaviorCoalesce);
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)refreshPrefs2, CFSTR("com.highrez.wificarrier/prefsupdated2"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
