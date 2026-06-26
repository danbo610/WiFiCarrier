// Import explicitly: the deprecated Theos Prefix.pch no longer auto-imports
// Foundation/UIKit when building against the iOS 14+ SDK, and this header is
// #include'd before Tweak.xm's own imports. UIKit transitively pulls in
// Foundation and CoreGraphics (NSObject, NSString, NSInteger, BOOL, UIView, etc.).
#import <UIKit/UIKit.h>

#define kWFCTapGesture 0xdeadbeef

@interface SBWiFiManager : NSObject
+(id)sharedInstance;
-(id)currentNetworkName;
-(BOOL)wiFiEnabled;
-(void)setWiFiEnabled:(BOOL)arg1;
@end

@interface STTelephonyStateProvider : NSObject
-(void)operatorNameChanged:(id)arg1 name:(id)arg2;
-(void)currentDataSimChanged:(id)arg1 ;
-(void)simStatusDidChange:(id)arg1 status:(id)arg2;
-(void)displayStatusChanged:(id)arg1 status:(id)arg2;
//-(void)dualSimCapabilityDidChange;
-(BOOL)isCellularRadioCapabilityActive;
-(BOOL)isRadioModuleDead;
-(BOOL)isDualSIMEnabled;
-(BOOL)isSIMPresentForSlot:(long long)arg1;
@end

@interface SBTelephonyManager : NSObject
+(id)sharedTelephonyManager;
-(STTelephonyStateProvider *)telephonyStateProvider;
-(void)operatorNameChanged:(id)arg1 name:(id)arg2;
-(void)simStatusDidChange:(id)arg1 status:(id)arg2;
-(id)SIMStatus;
-(BOOL)isUsingVPNConnection;
@end

@interface NEVPNConnection : NSObject 
-(void)setSession:(void*)arg1 ;
@end

@interface UIStatusBarWindow : UIWindow 
@end

// iOS 13 //
@interface UIStatusBarTapAction : NSObject
@property (nonatomic, readonly) NSInteger type;
@end

@interface SBMainDisplaySceneLayoutStatusBarView : UIView
- (void)_statusBarTapped:(id)sender type:(NSInteger)type;
@end

typedef enum {STATE_DISABLED = -1, STATE_SSID = 0, STATE_PUBLICIP = 1, STATE_INTERNALIP = 2, STATE_CUSTOMCARRIER = 3, STATE_ORIGINAL = 4} eState;
extern BOOL enableGesture;

// Statics //
static inline void forceUpdate();
static inline void GetPublicIP();

static inline NSString *GetNetworkNameOrIP();
static inline NSString *GetIPAddress();
static inline void MaybeFetchPublicIP();
static inline BOOL IsEmpty(id thing);
static inline NSString *GetCarrierText(id original);
static inline int SlotForContext(id ctx);
static inline void PublishCarrierName(int slot, id name);
static inline NSString *GetCarrierTextForSlot(int slot, id original);

extern int SlotForGesture(UIGestureRecognizer *recognizer);
extern void ChangeStateForSlot(int slot, UIView *host);
extern BOOL GestureAllowsLongPress();
extern BOOL GestureAllowsDoubleTap();
extern void Debug(id thing);
extern void DeleteDebugLog();

