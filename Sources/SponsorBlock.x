// Built-in SponsorBlock: auto-skips sponsor/self-promo/interaction segments.
// Uses the hash-prefix endpoint so the server never sees the exact video ID.

#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import "Settings.h"
#import "L10n.h"
#import "YTHeaders.h"
#import "Diagnostics.h"

static NSString *gSegVideoId;          // video the segments below belong to
static NSArray<NSArray *> *gSegments;  // @[ @[start, end], ... ]
static NSMutableSet<NSNumber *> *gSkipped;

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

    NSString *cats = @"[\"sponsor\",\"selfpromo\",\"interaction\"]";
    NSURLComponents *c = [NSURLComponents componentsWithString:
        [@"https://sponsor.ajay.app/api/skipSegments/" stringByAppendingString:SHA256Prefix(videoId, 4)]];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"categories" value:cats]];

    YTModLog(@"SponsorBlock: fetching segments for new video");
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
        for (NSDictionary *v in json) {
            if (![v isKindOfClass:NSDictionary.class] || ![v[@"videoID"] isEqual:videoId]) continue;
            for (NSDictionary *s in v[@"segments"]) {
                NSArray *seg = s[@"segment"];
                if ([seg isKindOfClass:NSArray.class] && seg.count == 2) [segs addObject:seg];
            }
        }
        YTModLog(@"SponsorBlock: HTTP %ld, %lu segment(s) for this video", (long)status, (unsigned long)segs.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([gSegVideoId isEqualToString:videoId]) gSegments = segs;
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

    NSString *vid = [player currentVideoID];
    if (!vid.length) return;
    if (![vid isEqualToString:gSegVideoId]) { FetchSegments(vid); return; }

    CGFloat t = [player currentVideoMediaTime];
    for (NSUInteger i = 0; i < gSegments.count; i++) {
        CGFloat start = [gSegments[i][0] doubleValue], end = [gSegments[i][1] doubleValue];
        if (t >= start && t < end - 0.5 && ![gSkipped containsObject:@(i)]) {
            [gSkipped addObject:@(i)];
            YTModLog(@"SponsorBlock: skipping %.1f -> %.1f", start, end);
            [player seekToTime:end];
            ShowToast(player.view, L10n(@"Skipped sponsor segment"));
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
