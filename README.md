# WiFiCarrier
Tweak to display the WiFi SSID or IP address as carrier. 
It also allows you to customize the carrier (network operator) text in the iOS status bar and to detect when WiFi Calling is enabled allowing you append custom text to the SSID / Custom Carrier

This is updated to work on iOS 13 as the orriginal did not. 
It should (from version 1.0.3) work on iOS 12 and perhaps older (it is currently untested on anything older than 12.4).

**From version 1.0.5** the tweak is ported to **iOS 16** and ships as **rootless** and **roothide** packages (arm64/arm64e, `Depends: ellekit`). The core hooks were verified against a live iOS 16.3.1 device. Both `.deb` variants are built in the cloud by GitHub Actions (`.github/workflows/build.yml`) on every push — download them from the run's *Artifacts*. Install the matching variant for your jailbreak (roothide → `*_roothide.deb`, rootless e.g. Dopamine → `*_rootless.deb`).

__Based on NoisyFlake's orriginal version with added functionality.__

# 
### Settings Explained (version 1.0.3)

#### Enable
Enable the tweak generally - simply an on/off switch!

#### Status Bar Gesture
Turns on a gesture on the status bar to cycle the displayed text through a fixed sequence:
**WiFi SSID → Public IP → Internal IP → Carrier (original)** and back to the start — regardless of which display options above are enabled. Each switch gives a short haptic tap and a brief on-screen toast naming the new mode.
NOTE: On iOS 13+ (incl. iOS 16) this gesture also works inside apps with a status bar.

#### Gesture Type
Choose how the gesture is triggered: **Long Press**, **Double Tap**, or **Both** (default).

#### Use WiFi SSID
Replace the carrier text with the WiFi Network Name (orriginal purpose of this tweak) when connected to WiFi.

#### Use IP Address
Replace the carrier text with your (internal) IP address on the WiFi network.

#### Public IP
Replace the carrier text with your public (exteral) IP address (WiFi/Cellular/VPN). 

**NOTE: A tiny data request is made to the URL below (default https://icanhazip.com/) to get this.**

#### URL (Public IP)
Shown only while Public IP is enabled. The endpoint queried for your public IP — it must return your IP as plain text. Defaults to `https://icanhazip.com/`; you can point it at any equivalent service (e.g. `https://api.ipify.org`) or your own.


### Custom Carrier
#### Enable
Enable custom carrier text (replace the carrier text with the specified Custom Carrier Text).

#### Custom Carrier Text
The text to replace the carrier text with. NOTE: This can be empty to clear the carrier text.


### WiFi Calling
WiFi Calling is available on some operators. It is an Apple feature that allows calls to be routed over WiFi when there is no cellular signal. Very handy for me as I get no signal at work!

#### Detect WiFi calling
Enable the detection of WiFi Calling. WiFi calling is simply detected by looking at the carrier text for certain content (Carrier WFC) and if that is there, WiFi calling is considered ON.

#### Carrier WFC:
The text to look for in the original carrier text. For example, my network, 3 (UK) normally show the carrier text "3" when on cellular. When on WiFi (and if WiFi calling is enabled in the Phone app), the carrier text changes to "Three WiFi Call" so you know that WiFi calling is on and working. Then calls and SMS work even with no service.

#### Add to SSID:
Text to append to the SSID (or IP address) when WiFi calling is enabled and the carrier text has been changed to the WiFi network name or IP adddress.

#### Add to Carrier:
Text to append to the SSID (or IP address) when WiFi calling is enabled and the SSID/IP Address options are disabled (thus just showing the custom carrier text). NOTE: You obviously still have to be on WiFi for WiFi calling to be on in the first place!


### Debugging
#### Enable
Write to a debug log file in the /tmp folder - this is really only useful during testing - it may be removed for release!

#### Send by Email
Send the debug log file by email to the developer (you can preview the content and redirect to someone else (like yourself) if you want to!

**NOTE: The debug log file is deleted if you disable debugging AND ALSO when an email is successfully sent.**
