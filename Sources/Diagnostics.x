// On-device debug log, exported from YTMod settings. Dumps the real ad-related
// class names and player-response field names of the running YouTube build, so
// hooks can target what actually exists instead of guessed names.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Diagnostics.h"

static const unsigned long long kMaxLogBytes = 2 * 1024 * 1024;

NSURL *YTModLogFileURL(void) {
    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                       inDomains:NSUserDomainMask].firstObject;
    return [docs URLByAppendingPathComponent:@"ytmod-log.txt"];
}

static dispatch_queue_t LogQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("ytmod.log", DISPATCH_QUEUE_SERIAL); });
    return q;
}

void YTModLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    dispatch_async(LogQueue(), ^{
        NSString *path = YTModLogFileURL().path;
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if ([h seekToEndOfFile] > kMaxLogBytes) return;
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    });
}

static NSArray<NSString *> *GPBFieldNames(Class cls) {
    if (!cls || ![cls respondsToSelector:@selector(descriptor)]) return @[];
    @try {
        id desc = [cls performSelector:@selector(descriptor)];
        NSMutableArray *names = [NSMutableArray array];
        for (id field in [desc valueForKey:@"fields"]) [names addObject:[field valueForKey:@"name"] ?: @"?"];
        return names;
    } @catch (id e) {
        return @[[NSString stringWithFormat:@"<descriptor failed: %@>", e]];
    }
}

// Player methods SponsorBlock relies on, plus any time/seek/videoID-like
// methods in case YouTube renamed them.
static void DumpPlayerMethods(void) {
    Class cls = objc_getClass("YTPlayerViewController");
    if (!cls) { YTModLog(@"YTPlayerViewController: class missing"); return; }
    for (NSString *s in @[@"singleVideo:currentVideoTimeDidChange:", @"currentVideoID",
                          @"currentVideoMediaTime", @"seekToTime:"])
        YTModLog(@"YTPlayerViewController %@: %@", s,
                 class_getInstanceMethod(cls, NSSelectorFromString(s)) ? @"yes" : @"NO");

    unsigned int n = 0;
    Method *methods = class_copyMethodList(cls, &n);
    NSMutableArray *hits = [NSMutableArray array];
    for (unsigned int i = 0; i < n; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lc = name.lowercaseString;
        if ([lc containsString:@"time"] || [lc containsString:@"seek"] || [lc containsString:@"videoid"])
            [hits addObject:name];
    }
    free(methods);
    [hits sortUsingSelector:@selector(compare:)];
    YTModLog(@"YTPlayerViewController time/seek/videoID methods: %@", [hits componentsJoinedByString:@" "]);
}

static void DumpRuntimeInfo(void) {
    YTModLog(@"=== YTMod diagnostics: YouTube %@ ===",
             NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]);
    DumpPlayerMethods();

    for (NSString *name in @[@"YTIPlayerResponse", @"YTIPlayabilityStatus"])
        YTModLog(@"fields %@: %@", name,
                 [GPBFieldNames(objc_getClass(name.UTF8String)) componentsJoinedByString:@", "]);

    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"(Ad|Ads)[A-Z]|Ad$|Ads$|Sponsor|Promo|SkipAd|Instream|Midroll|Preroll"
                             options:0 error:nil];
    unsigned int count = 0;
    const char **names = objc_copyClassNamesForImage(
        NSBundle.mainBundle.executablePath.fileSystemRepresentation, &count);
    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *n = @(names[i]);
        if ([re firstMatchInString:n options:0 range:NSMakeRange(0, n.length)]) [matches addObject:n];
    }
    free(names);
    [matches sortUsingSelector:@selector(compare:)];
    YTModLog(@"ad-like classes (%lu of %u):", (unsigned long)matches.count, count);
    for (NSUInteger i = 0; i < matches.count; i += 40)
        YTModLog(@"  %@", [[matches subarrayWithRange:NSMakeRange(i, MIN(40, matches.count - i))]
                              componentsJoinedByString:@" "]);
}

%ctor {
    [NSFileManager.defaultManager removeItemAtURL:YTModLogFileURL() error:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ DumpRuntimeInfo(); });
}
