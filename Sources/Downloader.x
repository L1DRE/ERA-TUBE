// Downloader — выбор формата + скачивание, при необходимости с деципшером
// signatureCipher через JSContext и муксом двух дорожек в один mp4.
//
// Логика по формату:
//   url present, no cipher                          -> прямой download
//   signatureCipher present                          -> SigDecipher -> download
//   высокое разрешение (video-only) + audio-only    -> качаем оба -> Muxer -> mp4

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import "Settings.h"
#import "SigDecipher.h"
#import "Muxer.h"
#import "L10n.h"

// --------- state ---------

static NSDictionary *gLastStreamingData;
static NSString     *gLastVideoTitle;
static NSString     *gLastVideoId;
static NSString     *gLastPlayerJsURL;   // "/s/player/XXX/player_ias.vflset/en_US/base.js"

// --------- helpers ---------

static NSString *SanitizeFilename(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\?%*|\"<>:"];
    return [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}

static UIViewController *TopVC(void) {
    UIWindow *w = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *x in ((UIWindowScene *)s).windows)
                if (x.isKeyWindow) { w = x; break; }
        }
        if (w) break;
    }
    UIViewController *c = w.rootViewController;
    while (c.presentedViewController) c = c.presentedViewController;
    return c;
}

static NSArray<NSDictionary *> *AllFormats(NSDictionary *streamingData) {
    NSMutableArray *all = [NSMutableArray array];
    for (NSString *k in @[@"formats", @"adaptiveFormats"]) {
        NSArray *a = streamingData[k];
        if ([a isKindOfClass:NSArray.class]) [all addObjectsFromArray:a];
    }
    return all;
}

static NSString *PickExtension(NSDictionary *fmt) {
    NSString *mime = fmt[@"mimeType"] ?: @"";
    if ([mime hasPrefix:@"video/mp4"]) return @"mp4";
    if ([mime hasPrefix:@"video/webm"]) return @"webm";
    if ([mime hasPrefix:@"audio/mp4"]) return @"m4a";
    if ([mime hasPrefix:@"audio/webm"]) return @"weba";
    return @"bin";
}

static BOOL IsH264(NSDictionary *fmt) {
    NSString *mime = fmt[@"mimeType"] ?: @"";
    return [mime containsString:@"avc1"] || [mime containsString:@"mp4a"];
}

// Получает годный к скачиванию URL из записи format.
// completion(nil, err) если декодировать нельзя.
static void ResolveFormatURL(NSDictionary *fmt, void (^cb)(NSString *url, NSError *err)) {
    NSString *url = fmt[@"url"];
    if (url.length) { cb(url, nil); return; }

    NSString *cipher = fmt[@"signatureCipher"] ?: fmt[@"cipher"];
    if (!cipher.length) { cb(nil, [NSError errorWithDomain:@"DL" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"no url & no cipher"}]); return; }

    [SigDecipher prepareWithPlayerJsURL:gLastPlayerJsURL
                             completion:^(BOOL ok, NSError *err) {
        if (!ok) { cb(nil, err); return; }
        NSString *final = [SigDecipher resolveSignatureCipher:cipher];
        if (!final) cb(nil, [NSError errorWithDomain:@"DL" code:2
            userInfo:@{NSLocalizedDescriptionKey:@"decipher failed"}]);
        else cb(final, nil);
    }];
}

static void SaveVideoToCameraRoll(NSURL *fileURL, UIViewController *host) {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                               handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized && st != PHAuthorizationStatusLimited) return;
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
        } completionHandler:^(BOOL ok, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *a = [UIAlertController
                    alertControllerWithTitle:L10n(ok ? @"Saved" : @"Save failed")
                                     message:ok ? L10n(@"Video added to Photos.") : err.localizedDescription
                              preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:L10n(@"OK")
                    style:UIAlertActionStyleDefault handler:nil]];
                [host presentViewController:a animated:YES completion:nil];
            });
        }];
    }];
}

static void ShareFile(NSURL *fileURL, UIViewController *host) {
    UIActivityViewController *vc = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    [host presentViewController:vc animated:YES completion:nil];
}

// Качает один URL в tmp-файл. cb вызывается в main queue.
static void DownloadToTmp(NSString *urlString, NSString *suffix,
                          void (^cb)(NSURL *file, NSError *err)) {
    NSURL *u = [NSURL URLWithString:urlString];
    if (!u) { cb(nil, [NSError errorWithDomain:@"DL" code:3 userInfo:nil]); return; }
    NSURLSessionDownloadTask *t = [[NSURLSession sharedSession]
        downloadTaskWithURL:u completionHandler:^(NSURL *tmp, NSURLResponse *r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (e || !tmp) { cb(nil, e); return; }
            NSString *fn = [NSString stringWithFormat:@"%@-%u.%@",
                SanitizeFilename(gLastVideoTitle ?: @"v"), arc4random(), suffix];
            NSURL *dst = [[NSFileManager.defaultManager temporaryDirectory]
                          URLByAppendingPathComponent:fn];
            [NSFileManager.defaultManager removeItemAtURL:dst error:nil];
            [NSFileManager.defaultManager moveItemAtURL:tmp toURL:dst error:nil];
            cb(dst, nil);
        });
    }];
    [t resume];
}

// --------- user-facing flows ---------

static UIAlertController *ShowProgress(UIViewController *host, NSString *title) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:@" "
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [host presentViewController:a animated:YES completion:nil];
    return a;
}

static void Finish(UIAlertController *progress, UIViewController *host,
                   NSError *err, NSURL *file, BOOL isVideo) {
    [progress dismissViewControllerAnimated:YES completion:^{
        if (err || !file) {
            UIAlertController *a = [UIAlertController alertControllerWithTitle:L10n(@"Failed")
                message:err.localizedDescription ?: @"unknown" preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:L10n(@"OK")
                style:UIAlertActionStyleDefault handler:nil]];
            [host presentViewController:a animated:YES completion:nil];
            return;
        }
        if (isVideo) SaveVideoToCameraRoll(file, host);
        else         ShareFile(file, host);
    }];
}

// Простой случай: одна дорожка (muxed или audio-only).
static void DownloadSingle(NSDictionary *fmt, BOOL isVideo, UIViewController *host) {
    UIAlertController *p = ShowProgress(host, L10n(@"Preparing…"));
    ResolveFormatURL(fmt, ^(NSString *url, NSError *e) {
        if (!url) { Finish(p, host, e, nil, isVideo); return; }
        DownloadToTmp(url, PickExtension(fmt), ^(NSURL *file, NSError *err) {
            Finish(p, host, err, file, isVideo);
        });
    });
}

// 1080p+: video-only + audio-only, потом mux в mp4.
static void DownloadAndMux(NSDictionary *vFmt, NSDictionary *aFmt, UIViewController *host) {
    UIAlertController *p = ShowProgress(host, L10n(@"Preparing video…"));
    ResolveFormatURL(vFmt, ^(NSString *vUrl, NSError *ve) {
        if (!vUrl) { Finish(p, host, ve, nil, YES); return; }
        ResolveFormatURL(aFmt, ^(NSString *aUrl, NSError *ae) {
            if (!aUrl) { Finish(p, host, ae, nil, YES); return; }
            dispatch_async(dispatch_get_main_queue(), ^{ p.title = L10n(@"Downloading video…"); });
            DownloadToTmp(vUrl, PickExtension(vFmt), ^(NSURL *vFile, NSError *e1) {
                if (!vFile) { Finish(p, host, e1, nil, YES); return; }
                dispatch_async(dispatch_get_main_queue(), ^{ p.title = L10n(@"Downloading audio…"); });
                DownloadToTmp(aUrl, PickExtension(aFmt), ^(NSURL *aFile, NSError *e2) {
                    if (!aFile) { Finish(p, host, e2, nil, YES); return; }
                    dispatch_async(dispatch_get_main_queue(), ^{ p.title = L10n(@"Muxing…"); });
                    NSString *fn = [NSString stringWithFormat:@"%@-%@p.mp4",
                        SanitizeFilename(gLastVideoTitle ?: @"v"), vFmt[@"height"]];
                    NSURL *out = [[NSFileManager.defaultManager temporaryDirectory]
                                  URLByAppendingPathComponent:fn];
                    [Muxer muxVideo:vFile audio:aFile outputURL:out
                         completion:^(BOOL ok, NSError *me) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [NSFileManager.defaultManager removeItemAtURL:vFile error:nil];
                            [NSFileManager.defaultManager removeItemAtURL:aFile error:nil];
                            Finish(p, host, ok ? nil : me, ok ? out : nil, YES);
                        });
                    }];
                });
            });
        });
    });
}

// --------- streamingData / jsUrl capture ---------

%hook YTIPlayerResponse
- (id)streamingData {
    id sd = %orig;
    @try {
        if ([sd respondsToSelector:@selector(dictionaryRepresentation)])
            gLastStreamingData = [sd performSelector:@selector(dictionaryRepresentation)];
    } @catch (__unused id e) {}
    return sd;
}
- (id)videoDetails {
    id vd = %orig;
    @try {
        NSString *t = [vd valueForKey:@"title"];
        NSString *v = [vd valueForKey:@"videoId"];
        if ([t isKindOfClass:NSString.class]) gLastVideoTitle = t;
        if ([v isKindOfClass:NSString.class]) gLastVideoId = v;
    } @catch (__unused id e) {}
    return vd;
}
- (id)playerConfig {
    id pc = %orig;
    @try {
        NSString *js = [pc valueForKeyPath:@"webPlayerConfig.webPlayerActionsPorting.jsUrl"];
        if (!js) js = [pc valueForKeyPath:@"assets.jsUrl"];
        if ([js isKindOfClass:NSString.class]) gLastPlayerJsURL = js;
    } @catch (__unused id e) {}
    return pc;
}
%end

// --------- UI ---------

%hook YTMainAppVideoPlayerOverlayViewController

- (void)didPressShare:(id)sender {
    if (!SettingsEnabled(@"downloader")) { %orig; return; }

    UIViewController *host = TopVC();
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:L10n(@"Download")
                         message:gLastVideoTitle ?: L10n(@"Pick a format")
                  preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *fmts = AllFormats(gLastStreamingData);

    NSMutableArray<NSDictionary *> *muxed = [NSMutableArray new];   // video+audio в одной дорожке
    NSMutableArray<NSDictionary *> *videoOnly = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *audioOnly = [NSMutableArray new];
    for (NSDictionary *f in fmts) {
        if (![f isKindOfClass:NSDictionary.class]) continue;
        NSString *mime = f[@"mimeType"] ?: @"";
        BOOL hasAudio = [mime containsString:@"mp4a"] || [mime containsString:@"opus"]
                     || [mime containsString:@"vorbis"];
        BOOL hasVideo = f[@"width"] != nil;
        if (hasVideo && hasAudio) [muxed addObject:f];
        else if (hasVideo)        [videoOnly addObject:f];
        else if (hasAudio)        [audioOnly addObject:f];
    }

    NSComparator byHeight = ^(NSDictionary *a, NSDictionary *b) {
        return [b[@"height"] compare:a[@"height"]];
    };
    [muxed sortUsingComparator:byHeight];
    [videoOnly sortUsingComparator:byHeight];
    [audioOnly sortUsingComparator:^(NSDictionary *a, NSDictionary *b) {
        return [b[@"bitrate"] compare:a[@"bitrate"]];
    }];

    // muxed (без лишних шагов)
    for (NSDictionary *f in muxed) {
        NSString *t = [NSString stringWithFormat:L10n(@"muxed_fmt"),
                       f[@"height"], PickExtension(f)];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) { DownloadSingle(f, YES, host); }]];
    }

    // video-only + лучший H.264 audio -> mux
    NSDictionary *bestAudioH264 = nil;
    for (NSDictionary *a in audioOnly) if (IsH264(a)) { bestAudioH264 = a; break; }
    for (NSDictionary *v in videoOnly) {
        if (!IsH264(v)) continue;        // Пропустить VP9/AV1: iOS не замуксует.
        if (!bestAudioH264) break;
        NSString *t = [NSString stringWithFormat:L10n(@"muxed_mp4_fmt"), v[@"height"]];
        [sheet addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *_) { DownloadAndMux(v, bestAudioH264, host); }]];
    }

    if (audioOnly.count) {
        NSDictionary *best = bestAudioH264 ?: audioOnly.firstObject;
        [sheet addAction:[UIAlertAction actionWithTitle:
            [NSString stringWithFormat:L10n(@"Audio-only (%@)"), PickExtension(best)]
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
                DownloadSingle(best, NO, host);
            }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:L10n(@"Share (system)")
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) { %orig; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:L10n(@"Cancel")
        style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = host.view;
    sheet.popoverPresentationController.sourceRect =
        CGRectMake(host.view.bounds.size.width / 2, host.view.bounds.size.height - 40, 1, 1);
    [host presentViewController:sheet animated:YES completion:nil];
}

%end
