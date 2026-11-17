// SigDecipher — минимальный порт логики yt-dlp:
//   1) Качаем https://www.youtube.com<jsUrl> (base.js плеера).
//   2) Регэкспами вытягиваем:
//        - имя decipher-функции и её тело
//        - имя транс-объекта (swap/reverse/splice) и его методы
//        - имя n-функции (anti-throttling) и её тело
//   3) Склеиваем это в маленький JS-модуль и исполняем через JavaScriptCore.
//   4) resolveSignatureCipher / applyNParam дергают готовые JS-функции.
//
// Регэкспы валидны на plateau YouTube 2023–2025. При очередном крупном ребренде
// плеера имена меняются — тогда правь паттерны ниже (`kSigNamePat`, `kNFuncPat`).

#import "SigDecipher.h"
#import <JavaScriptCore/JavaScriptCore.h>

static JSContext *gCtx;
static NSString  *gLastJsURL;

#pragma mark - regex helpers

static NSString *FirstMatch(NSString *src, NSString *pattern, NSInteger group) {
    NSError *e = nil;
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                      options:0 error:&e];
    if (!r) return nil;
    NSTextCheckingResult *m = [r firstMatchInString:src options:0
                                              range:NSMakeRange(0, src.length)];
    if (!m || m.numberOfRanges <= group) return nil;
    NSRange rg = [m rangeAtIndex:group];
    if (rg.location == NSNotFound) return nil;
    return [src substringWithRange:rg];
}

#pragma mark - base.js parsing

static NSString *const kSigNamePat =
    @"\\b([a-zA-Z0-9$_]+)\\s*=\\s*function\\(\\s*([a-zA-Z0-9$_]+)\\s*\\)\\s*\\{\\s*\\2\\s*=\\s*\\2\\.split\\(\"\"\\)";

static NSString *const kNFuncPat =
    @"\\b([a-zA-Z0-9$_]+)=function\\(\\s*([a-zA-Z0-9$_]+)\\s*\\)\\{var \\2=\\2\\.split\\([\"']{2}[\"']?\\)";

static NSString *ExtractFunctionBody(NSString *js, NSString *name) {
    // Ищем "<name>=function(a){...};"
    NSString *escaped = [NSRegularExpression escapedPatternForString:name];
    NSString *pat = [NSString stringWithFormat:
        @"(?:var\\s+)?%@\\s*=\\s*function\\s*\\([^)]*\\)\\s*\\{", escaped];
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:pat
                                                                      options:0 error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:js options:0
                                              range:NSMakeRange(0, js.length)];
    if (!m) return nil;

    NSUInteger start = m.range.location;
    NSUInteger i = NSMaxRange(m.range) - 1;   // позиция '{'
    NSInteger depth = 0;
    while (i < js.length) {
        unichar c = [js characterAtIndex:i];
        if (c == '{') depth++;
        else if (c == '}') { depth--; if (depth == 0) { i++; break; } }
        i++;
    }
    if (i <= start) return nil;
    return [js substringWithRange:NSMakeRange(start, i - start)] ;
}

static NSString *ExtractTransObject(NSString *js, NSString *sigBody) {
    // В теле sig-функции встречается вызов <obj>.<method>(a, N). Берем имя объекта,
    // потом вырезаем var <obj>={ ... };
    NSString *obj = FirstMatch(sigBody, @";\\s*([a-zA-Z0-9$_]+)\\s*\\.", 1);
    if (!obj) return nil;
    NSString *escaped = [NSRegularExpression escapedPatternForString:obj];
    NSString *pat = [NSString stringWithFormat:@"var\\s+%@\\s*=\\s*\\{", escaped];
    NSRegularExpression *r = [NSRegularExpression regularExpressionWithPattern:pat
                                                                      options:0 error:nil];
    NSTextCheckingResult *m = [r firstMatchInString:js options:0
                                              range:NSMakeRange(0, js.length)];
    if (!m) return nil;
    NSUInteger start = m.range.location;
    NSUInteger i = NSMaxRange(m.range) - 1;
    NSInteger depth = 0;
    while (i < js.length) {
        unichar c = [js characterAtIndex:i];
        if (c == '{') depth++;
        else if (c == '}') { depth--; if (depth == 0) { i++; break; } }
        i++;
    }
    if (i <= start) return nil;
    NSString *body = [js substringWithRange:NSMakeRange(start, i - start)];
    return [body stringByAppendingString:@";"];
}

#pragma mark - public

@implementation SigDecipher

+ (void)prepareWithPlayerJsURL:(NSString *)jsURL
                    completion:(void (^)(BOOL, NSError *))completion {
    if (!jsURL.length) { completion(NO, nil); return; }
    NSString *full = [jsURL hasPrefix:@"http"] ? jsURL
                   : [@"https://www.youtube.com" stringByAppendingString:jsURL];
    if ([full isEqualToString:gLastJsURL] && gCtx) { completion(YES, nil); return; }

    NSURL *u = [NSURL URLWithString:full];
    [[[NSURLSession sharedSession] dataTaskWithURL:u
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) { completion(NO, err); return; }
        NSString *js = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *sigName  = FirstMatch(js, kSigNamePat, 1);
        NSString *sigBody  = sigName ? ExtractFunctionBody(js, sigName) : nil;
        NSString *transObj = sigBody ? ExtractTransObject(js, sigBody) : nil;
        NSString *nName    = FirstMatch(js, kNFuncPat, 1);
        NSString *nBody    = nName ? ExtractFunctionBody(js, nName) : nil;

        if (!sigName || !sigBody || !transObj) {
            completion(NO, [NSError errorWithDomain:@"SigDecipher" code:1
                userInfo:@{NSLocalizedDescriptionKey:@"regex miss, player updated"}]);
            return;
        }

        NSMutableString *src = [NSMutableString new];
        [src appendString:transObj];
        [src appendString:sigBody];
        [src appendString:@";\n"];
        if (nBody) [src appendFormat:@"%@;\n", nBody];

        [src appendFormat:@"\nfunction __sig(s){return %@(s);}\n", sigName];
        if (nName)
            [src appendFormat:@"function __n(s){return %@(s);}\n", nName];
        else
            [src appendString:@"function __n(s){return s;}\n"];

        gCtx = [[JSContext alloc] init];
        gCtx.exceptionHandler = ^(JSContext *c, JSValue *ex) {
            NSLog(@"[YTMod][JS] %@", ex);
        };
        [gCtx evaluateScript:src];
        gLastJsURL = full;
        completion(gCtx.exception == nil, nil);
    }] resume];
}

+ (NSString *)resolveSignatureCipher:(NSString *)sc {
    if (!gCtx || !sc.length) return nil;
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSString *kv in [sc componentsSeparatedByString:@"&"]) {
        NSRange r = [kv rangeOfString:@"="];
        if (r.location == NSNotFound) continue;
        NSString *k = [kv substringToIndex:r.location];
        NSString *v = [[kv substringFromIndex:r.location+1]
                       stringByRemovingPercentEncoding] ?: @"";
        parts[k] = v;
    }
    NSString *s = parts[@"s"], *sp = parts[@"sp"] ?: @"sig", *url = parts[@"url"];
    if (!s || !url) return nil;

    JSValue *decoded = [gCtx[@"__sig"] callWithArguments:@[s]];
    NSString *dec = [decoded toString];
    if (!dec.length) return nil;

    NSString *finalURL = [url stringByAppendingFormat:
        @"&%@=%@", sp,
        [dec stringByAddingPercentEncodingWithAllowedCharacters:
            NSCharacterSet.URLQueryAllowedCharacterSet]];
    return [self applyNParam:finalURL] ?: finalURL;
}

+ (NSString *)applyNParam:(NSString *)url {
    if (!gCtx) return url;
    NSURLComponents *c = [NSURLComponents componentsWithString:url];
    NSMutableArray<NSURLQueryItem *> *items = [c.queryItems mutableCopy] ?: [NSMutableArray new];
    for (NSInteger i = 0; i < items.count; i++) {
        NSURLQueryItem *q = items[i];
        if (![q.name isEqualToString:@"n"]) continue;
        JSValue *v = [gCtx[@"__n"] callWithArguments:@[q.value ?: @""]];
        NSString *nn = [v toString];
        if (nn.length) items[i] = [NSURLQueryItem queryItemWithName:@"n" value:nn];
    }
    c.queryItems = items;
    return c.URL.absoluteString;
}

@end
