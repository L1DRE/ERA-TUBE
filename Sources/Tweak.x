// YTMod — core hooks
// Covers: ad removal, background playback, PiP forced on, Shorts hiding, misc UI cleanup.
// Known-good class/method names for current YouTube iOS builds (Dec 2025 era).
// If YouTube ships an update that renames a symbol, adjust the matching hook.

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import "Settings.h"

// ---------- 1. Ad removal ----------

%hook YTIPlayerResponse
- (NSArray *)adBreaks { return SettingsEnabled(@"adsOff") ? @[] : %orig; }
- (NSArray *)adSlots { return SettingsEnabled(@"adsOff") ? @[] : %orig; }
- (id)playerAds { return SettingsEnabled(@"adsOff") ? nil : %orig; }
%end

%hook YTIElementRenderer
- (NSData *)elementData {
    NSData *d = %orig;
    if (!SettingsEnabled(@"adsOff") || !d) return d;
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if ([s containsString:@"brand_promo"] ||
        [s containsString:@"product_carousel"] ||
        [s containsString:@"text_search_ad"] ||
        [s containsString:@"shorts_shelf"] ||
        [s containsString:@"ads"]) return nil;
    return d;
}
%end

// ---------- 2. Background playback ----------

%hook YTSingleVideo
- (BOOL)isAirPlayPlaying { return SettingsEnabled(@"background") ? YES : %orig; }
%end

%hook YTIPlayerStatsClientPlaybackNonceSupportedRenderer
- (BOOL)backgroundable { return SettingsEnabled(@"background") ? YES : %orig; }
%end

%hook MLABRPolicy
- (BOOL)isPlaybackBackgroundable { return SettingsEnabled(@"background") ? YES : %orig; }
%end

// Force audio session to .playback so sound continues when screen locks.
%hook YTMainAppVideoPlayerOverlayViewController
- (void)viewDidLoad {
    %orig;
    if (SettingsEnabled(@"background")) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
    }
}
%end

// ---------- 3. Picture-in-Picture ----------

%hook MLHAMSBDLManager
- (BOOL)isPictureInPictureSupported { return SettingsEnabled(@"pip") ? YES : %orig; }
- (BOOL)pictureInPictureWasStartedWhenSuspended { return SettingsEnabled(@"pip") ? YES : %orig; }
%end

%hook YTPlayerPIPController
- (BOOL)canEnterPictureInPicture { return SettingsEnabled(@"pip") ? YES : %orig; }
%end

// ---------- 4. UI tweaks ----------

%hook YTPivotBarView
- (void)setItems:(NSArray *)items {
    if (!SettingsEnabled(@"hideShorts")) { %orig; return; }
    NSMutableArray *filtered = [NSMutableArray array];
    for (id item in items) {
        NSString *title = [[item valueForKey:@"title"] description] ?: @"";
        if ([title.lowercaseString containsString:@"shorts"]) continue;
        [filtered addObject:item];
    }
    %orig(filtered);
}
%end

%hook YTReelHeaderView
- (void)layoutSubviews {
    %orig;
    if (SettingsEnabled(@"hideShorts")) self.hidden = YES;
}
%end

// Hide "You" tab notification dot / misc overlays.
%hook YTChannelMobileHeaderViewController
- (void)setBrandingHeaderData:(id)d {
    if (SettingsEnabled(@"hideBranding")) return;
    %orig;
}
%end

// Remove in-video overlays (end cards, subscribe prompts) when adsOff on.
%hook YTMainAppVideoPlayerOverlayView
- (void)setBrandingOverlayViewVisible:(BOOL)v {
    %orig(SettingsEnabled(@"adsOff") ? NO : v);
}
%end

// ---------- 5. ctor ----------

%ctor {
    SettingsLoad();
    %init;
}
