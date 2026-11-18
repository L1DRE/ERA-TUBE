// YTMod — core hooks: ad removal, background playback, PiP, Shorts hiding.
// If YouTube ships an update that renames a symbol, adjust the matching hook.

#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import "Settings.h"
#import "YTHeaders.h"

// ---------- 1. Ad removal ----------

#define ADS_OFF SettingsEnabled(@"adsOff")

// Video ads: stop the ads context from being sent with player requests and
// treat every video as unmonetized, so no ad breaks are scheduled.
%hook YTIPlayerResponse
- (BOOL)isMonetized { return ADS_OFF ? NO : %orig; }
%end

%hook YTAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { if (!ADS_OFF) %orig; }
%end

%hook YTAccountScopedAdsInnerTubeContextDecorator
- (void)decorateContext:(id)context { if (!ADS_OFF) %orig; }
%end

%hook YTDataUtils
+ (id)spamSignalsDictionary              { return ADS_OFF ? nil : %orig; }
+ (id)spamSignalsDictionaryWithoutIDFA   { return ADS_OFF ? nil : %orig; }
%end

%hook YTLocalPlaybackController
- (id)createAdsPlaybackCoordinator { return ADS_OFF ? nil : %orig; }
%end

// Feed / search ads arrive as sections whose first item is a promoted renderer
// or an element renderer whose type names an ad layout.
static id KV(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

// Ad elements carry ad-impression logging data; ordinary content does not.
static BOOL HasAdLoggingData(id element) {
    if (![KV(element, @"hasCompatibilityOptions") boolValue]) return NO;
    return [KV(KV(element, @"compatibilityOptions"), @"hasAdLoggingData") boolValue];
}

static BOOL IsAdElement(id element) {
    if (!element) return NO;
    if (HasAdLoggingData(element)) return YES;
    static NSArray *markers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markers = @[@"brand_promo", @"carousel_footered_layout", @"carousel_headered_layout",
                    @"feed_ad_metadata", @"full_width_portrait_image_layout",
                    @"full_width_square_image_layout", @"landscape_image_wide_button_layout",
                    @"product_carousel", @"product_engagement_panel", @"product_item",
                    @"shopping_carousel", @"shopping_item_card_list", @"statement_banner",
                    @"square_image_layout", @"text_image_button_layout", @"text_search_ad",
                    @"video_display_full_layout", @"video_display_full_buttoned_layout"];
    });
    NSString *desc = [element description];
    for (NSString *m in markers) if ([desc containsString:m]) return YES;
    return NO;
}

static BOOL IsAdSection(id renderers) {
    NSArray *items = KV(KV(renderers, @"itemSectionRenderer"), @"contentsArray");
    id first = [items isKindOfClass:NSArray.class] ? items.firstObject : nil;
    if (!first) return NO;
    for (NSString *k in @[@"hasPromotedVideoRenderer", @"hasCompactPromotedVideoRenderer",
                          @"hasPromotedVideoInlineMutedRenderer"])
        if ([KV(first, k) boolValue]) return YES;
    return IsAdElement(KV(first, @"elementRenderer"));
}

// Catches ad cards wherever they render (feed, search, under the player),
// even when they are not the first item of their section.
// Only the cheap flag check here: -description is costly and may read elementData.
%hook YTIElementRenderer
- (NSData *)elementData {
    return (ADS_OFF && HasAdLoggingData(self)) ? nil : %orig;
}
%end

%hook YTInnerTubeCollectionViewController
- (void)loadWithModel:(id)model {
    if (ADS_OFF && [model isKindOfClass:%c(YTISectionListRenderer)]) {
        NSMutableArray *contents = KV(model, @"contentsArray");
        if ([contents isKindOfClass:NSMutableArray.class]) {
            NSIndexSet *ads = [contents indexesOfObjectsPassingTest:^BOOL(id r, NSUInteger i, BOOL *stop) {
                return IsAdSection(r);
            }];
            [contents removeObjectsAtIndexes:ads];
        }
    }
    %orig;
}
%end

// ---------- 2. Background playback ----------

#define BG_ON SettingsEnabled(@"background")

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return BG_ON ? YES : %orig; }
%end

%hook MLVideo
- (BOOL)playableInBackground { return BG_ON ? YES : %orig; }
%end

%hook YTIBackgroundOfflineSettingCategoryEntryRenderer
- (BOOL)isBackgroundEnabled { return BG_ON ? YES : %orig; }
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
