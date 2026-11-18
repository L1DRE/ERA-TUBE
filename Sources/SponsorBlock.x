// Built-in SponsorBlock: auto-skips sponsor/self-promo/interaction segments and,
// behind a second toggle, the extra categories ReVanced uses.
// Uses the hash-prefix endpoint so the server never sees the exact video ID.

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "Settings.h"
#import "L10n.h"
#import "YTHeaders.h"
#import "Diagnostics.h"

static NSString *gSegVideoId;          // video the segments below belong to
static NSArray<NSDictionary *> *gSegments;  // @[ @{start, end, category}, ... ]
static NSMutableSet<NSNumber *> *gSkipped;
static CGFloat gDuration;              // video length in seconds, for marker positions
static NSHashTable<UIView *> *gBars;   // live player bars to redraw markers on

static const NSInteger kMarkerTag = 0x5B5B;

static NSArray<NSString *> *Categories(void) {
    NSMutableArray *c = [@[@"sponsor", @"selfpromo", @"interaction"] mutableCopy];
    if (SettingsEnabled(@"sponsorBlockExtra"))
        [c addObjectsFromArray:@[@"intro", @"outro", @"preview", @"filler", @"music_offtopic"]];
    return c;
}

// SponsorBlock's standard category colors.
static UIColor *CategoryColor(NSString *category) {
    static NSDictionary *hex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hex = @{@"sponsor": @0x00D400, @"selfpromo": @0xFFFF00, @"interaction": @0xCC00FF,
                @"intro": @0x00FFFF, @"outro": @0x0202ED, @"preview": @0x008FD6,
                @"filler": @0x7300FF, @"music_offtopic": @0xFF9900};
    });
    unsigned int v = [hex[category] unsignedIntValue] ?: 0x00D400;
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0 alpha:0.9];
}

static id KVBar(id obj, NSString *key) {
    if (!obj) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused id e) { return nil; }
}

static void DrawMarkers(UIView *bar) {
    for (UIView *v in [bar.subviews copy]) if (v.tag == kMarkerTag) [v removeFromSuperview];

    // Log each bar class once, so the debug log shows which one is actually on screen.
    static NSMutableSet *seenClasses;
    if (!seenClasses) seenClasses = [NSMutableSet set];
    NSString *cls = NSStringFromClass(bar.class);
    if (![seenClasses containsObject:cls]) {
        [seenClasses addObject:cls];
        YTModLog(@"SponsorBlock: bar %@ size %.0fx%.0f, window %@", cls,
                 bar.bounds.size.width, bar.bounds.size.height, bar.window ? @"yes" : @"no");
    }

    if (!SettingsEnabled(@"sponsorBlock") || !gSegments.count) return;

    // The visible progress track is a decoration subview; markers sit exactly on it.
    UIView *track = nil;
    for (UIView *v in bar.subviews) {
        NSString *n = NSStringFromClass(v.class);
        if ([n isEqualToString:@"YTPlayerBarRectangleDecorationView"]) { track = v; break; }
        if (!track && [n isEqualToString:@"YTPlayerBarProgressDecorationView"]) track = v;
    }
    // Without a track, only draw on bar-shaped views, never over a whole container.
    if (!track && (bar.bounds.size.height > 40 || bar.bounds.size.width < 50)) return;

    // Duration fallback from the bar itself (its own total time or its model).
    CGFloat duration = gDuration;
    if (duration <= 0) duration = [KVBar(bar, @"totalTime") doubleValue];
    if (duration <= 0) duration = [KVBar(KVBar(KVBar(bar, @"_model"), @"playingState"), @"totalTimeSec") doubleValue];
    if (duration <= 0) return;

    static NSString *loggedFor;
    if (![loggedFor isEqualToString:gSegVideoId]) {
        loggedFor = gSegVideoId;
        YTModLog(@"SponsorBlock: drawing %lu marker(s) on %@ (track %@), duration %.0fs",
                 (unsigned long)gSegments.count, cls, track ? NSStringFromClass(track.class) : @"none", duration);
    }

    CGFloat w = bar.bounds.size.width;
    CGFloat h = track ? MAX(2, track.frame.size.height) : 3;
    CGFloat y = track ? track.frame.origin.y : (bar.bounds.size.height - h) / 2;
    for (NSDictionary *seg in gSegments) {
        CGFloat start = [seg[@"start"] doubleValue], end = [seg[@"end"] doubleValue];
        UIView *m = [[UIView alloc] initWithFrame:CGRectMake(w * start / duration, y,
                                                             MAX(2, w * (end - start) / duration), h)];
        m.tag = kMarkerTag;
        m.userInteractionEnabled = NO;
        m.backgroundColor = CategoryColor(seg[@"category"]);
        if (track) [bar insertSubview:m aboveSubview:track];
        else [bar addSubview:m];
    }
}

static void RefreshMarkers(void) {
    for (UIView *bar in gBars) [bar setNeedsLayout];
}

static NSString *SHA256Prefix(NSString *s, NSUInteger len) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", h[i]];
    return [hex substringToIndex:len];
}

static void FetchSegments(NSString *videoId) {
    gSegVideoId = videoId;
    gSegments = @[];
    gSkipped = [NSMutableSet set];
    gDuration = 0;
    RefreshMarkers();

    NSData *catsJSON = [NSJSONSerialization dataWithJSONObject:Categories() options:0 error:nil];
    NSString *cats = [[NSString alloc] initWithData:catsJSON encoding:NSUTF8StringEncoding];
    NSURLComponents *c = [NSURLComponents componentsWithString:
        [@"https://sponsor.ajay.app/api/skipSegments/" stringByAppendingString:SHA256Prefix(videoId, 4)]];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"categories" value:cats]];

    // Shape only (no ID itself): a real video ID is 11 chars of [A-Za-z0-9_-].
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    BOOL wellFormed = videoId.length == 11 && [videoId rangeOfCharacterFromSet:bad].location == NSNotFound;
    YTModLog(@"SponsorBlock: fetching segments for new video (id length %lu, %@)",
             (unsigned long)videoId.length, wellFormed ? @"well-formed" : @"MALFORMED");
    [[[NSURLSession sharedSession] dataTaskWithURL:c.URL
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (err || !data) { YTModLog(@"SponsorBlock: request failed (%ld) %@", (long)status, err); return; }
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSArray.class]) {
            YTModLog(@"SponsorBlock: HTTP %ld, no segments for this hash prefix", (long)status);
            return;
        }
        NSMutableArray *segs = [NSMutableArray array];
        CGFloat apiDuration = 0;
        for (NSDictionary *v in json) {
            if (![v isKindOfClass:NSDictionary.class] || ![v[@"videoID"] isEqual:videoId]) continue;
            for (NSDictionary *s in v[@"segments"]) {
                NSArray *seg = s[@"segment"];
                // actionType "full" labels the whole video; "mute" isn't a skip.
                NSString *action = s[@"actionType"];
                if (action && ![action isEqualToString:@"skip"]) continue;
                if ([seg isKindOfClass:NSArray.class] && seg.count == 2)
                    [segs addObject:@{@"start": seg[0], @"end": seg[1],
                                      @"category": s[@"category"] ?: @"sponsor"}];
                apiDuration = MAX(apiDuration, [s[@"videoDuration"] doubleValue]);
            }
        }
        YTModLog(@"SponsorBlock: HTTP %ld, %lu video(s) share the hash prefix, %lu segment(s) for this video",
                 (long)status, (unsigned long)[json count], (unsigned long)segs.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![gSegVideoId isEqualToString:videoId]) return;
            gSegments = segs;
            if (apiDuration > 0) gDuration = apiDuration;
            RefreshMarkers();
        });
    }] resume];
}

static void ShowToast(UIView *host, NSString *text) {
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:@"  %@  ", text];
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    l.layer.cornerRadius = 8;
    l.clipsToBounds = YES;
    [l sizeToFit];
    l.center = CGPointMake(host.bounds.size.width / 2, host.bounds.size.height - 60);
    [host addSubview:l];
    [UIView animateWithDuration:0.3 delay:1.5 options:0 animations:^{ l.alpha = 0; }
                     completion:^(BOOL f) { [l removeFromSuperview]; }];
}

static void SponsorBlockTick(YTPlayerViewController *player) {
    static int calls;
    if (calls++ == 0) YTModLog(@"SponsorBlock: time-change hook fires");
    if (!SettingsEnabled(@"sponsorBlock")) return;

    if (![player respondsToSelector:@selector(currentVideoID)] ||
        ![player respondsToSelector:@selector(currentVideoMediaTime)] ||
        ![player respondsToSelector:@selector(seekToTime:)]) {
        static BOOL warned;
        if (!warned) { warned = YES; YTModLog(@"SponsorBlock: player methods missing, disabled"); }
        return;
    }

    // "content" variants refer to the main video even while an ad plays.
    BOOL content = [player respondsToSelector:@selector(contentVideoID)] &&
                   [player respondsToSelector:@selector(contentVideoMediaTime)];
    NSString *vid = content ? [player contentVideoID] : [player currentVideoID];
    if (!vid.length) return;
    if (![vid isEqualToString:gSegVideoId]) { FetchSegments(vid); return; }

    // Fallback duration from the player, only while the main video (not an ad) is current.
    if (gDuration <= 0 && gSegments.count &&
        [player respondsToSelector:@selector(currentVideoTotalMediaTime)] &&
        (!content || [[player contentVideoID] isEqualToString:[player currentVideoID]])) {
        gDuration = [player currentVideoTotalMediaTime];
        if (gDuration > 0) RefreshMarkers();
    }

    CGFloat t = content ? [player contentVideoMediaTime] : [player currentVideoMediaTime];
    for (NSUInteger i = 0; i < gSegments.count; i++) {
        CGFloat start = [gSegments[i][@"start"] doubleValue], end = [gSegments[i][@"end"] doubleValue];
        if (t >= start && t < end - 0.5 && ![gSkipped containsObject:@(i)]) {
            [gSkipped addObject:@(i)];
            YTModLog(@"SponsorBlock: skipping %@ %.1f -> %.1f", gSegments[i][@"category"], start, end);
            [player seekToTime:end];
            ShowToast(player.view, L10n([gSegments[i][@"category"] isEqualToString:@"sponsor"]
                                        ? @"Skipped sponsor segment" : @"Skipped segment"));
            break;
        }
    }
}

%hook YTPlayerViewController

// YouTube 21.46 renamed the time callback (confirmed by the debug log); the
// old name is kept for other builds.
- (void)potentiallyMutatedSingleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    SponsorBlockTick(self);
}

- (void)singleVideo:(id)video currentVideoTimeDidChange:(id)time {
    %orig;
    SponsorBlockTick(self);
}

%end

// Segment markers on the main video progress bar. Which class draws the visible
// bar depends on the player design, so several candidates are hooked.
static void BarDidLayout(UIView *bar) {
    if (!gBars) gBars = [NSHashTable weakObjectsHashTable];
    [gBars addObject:bar];
    DrawMarkers(bar);
}

%hook YTInlinePlayerBarView
- (void)layoutSubviews { %orig; BarDidLayout(self); }
%end

%hook YTModularPlayerBarView
- (void)layoutSubviews { %orig; BarDidLayout(self); }
%end

%hook YTPlayerBarSegmentedProgressView
- (void)layoutSubviews { %orig; BarDidLayout(self); }
%end

%hook YTPlayerBarView
- (void)layoutSubviews { %orig; BarDidLayout(self); }
%end

// The container knows which bar is current: the modular bar (via its controller's
// view) in newer designs, the segmentable inline bar in older ones.
%hook YTInlinePlayerBarContainerView
- (void)layoutSubviews {
    %orig;
    id bar = KVBar(self, @"modularPlayerBar") ?: KVBar(self, @"segmentablePlayerBar");
    if (![bar isKindOfClass:UIView.class]) bar = KVBar(bar, @"view");
    if ([bar isKindOfClass:UIView.class]) BarDidLayout(bar);
}
%end
