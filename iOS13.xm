//
//This file is for iOS 13+ Only
//

#include "Tweak.h"
#include "Version.h"

%group iOS13

	// For IOS13 status bar IN APP... Runs in SpringBoard; forwards status bar events to app
	%hook SBMainDisplaySceneLayoutStatusBarView
	- (void)_addStatusBarIfNeeded {
		%orig;
		UIView *statusBar = [self valueForKey:@"_statusBar"];
		[statusBar addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(wfcGestureHandler:)
		]];
		UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(wfcDoubleTapHandler:)];
		doubleTap.numberOfTapsRequired = 2;
		[statusBar addGestureRecognizer:doubleTap];
	}

	%new
	- (void)wfcGestureHandler:(UILongPressGestureRecognizer  *)recognizer {
		if (enableGesture && GestureAllowsLongPress() && recognizer.state == UIGestureRecognizerStateBegan) {
			ChangeState(recognizer.view);
		}
	}

	%new
	- (void)wfcDoubleTapHandler:(UITapGestureRecognizer *)recognizer {
		if (enableGesture && GestureAllowsDoubleTap() && recognizer.state == UIGestureRecognizerStateRecognized) {
			ChangeState(recognizer.view);
		}
	}
	%end // SBMainDisplaySceneLayoutStatusBarView

%end // iOS13StatusBar

%ctor {
	if (@available(iOS 13, *)) {
		%init(iOS13);
	}
}
