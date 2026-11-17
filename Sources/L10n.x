#import "L10n.h"
#import "Settings.h"
#import <dlfcn.h>

static NSBundle *gResBundle;      // YTModResources.bundle
static NSBundle *gLangBundle;     // .lproj внутри него
static NSString *gCurrentLang;

static NSArray *kLanguages(void) {
    return @[@"en", @"ru", @"kk", @"uk", @"es", @"de", @"fr", @"pt-BR", @"ja", @"zh-Hans"];
}

static NSBundle *LoadResourceBundle(void) {
    // Ищем бандл рядом с нашей .dylib (tweak), затем в YouTube.app.
    Dl_info info;
    if (dladdr((const void *)&LoadResourceBundle, &info) && info.dli_fname) {
        NSString *dir = [@(info.dli_fname) stringByDeletingLastPathComponent];
        for (NSString *name in @[@"YTModResources.bundle", @"YTMod.bundle"]) {
            NSString *p = [dir stringByAppendingPathComponent:name];
            if ([NSFileManager.defaultManager fileExistsAtPath:p])
                return [NSBundle bundleWithPath:p];
        }
    }
    NSString *p = [NSBundle.mainBundle pathForResource:@"YTModResources" ofType:@"bundle"];
    if (p) return [NSBundle bundleWithPath:p];
    // Jailbreak .deb: rootful и rootless пути.
    for (NSString *jb in @[@"/Library/Application Support/YTMod/YTModResources.bundle",
                           @"/var/jb/Library/Application Support/YTMod/YTModResources.bundle"]) {
        if ([NSFileManager.defaultManager fileExistsAtPath:jb])
            return [NSBundle bundleWithPath:jb];
    }
    return nil;
}

static NSString *PickLanguage(NSArray *supported) {
    NSString *forced = [[NSUserDefaults standardUserDefaults] stringForKey:@"ytmod.language"];
    if (forced.length && [supported containsObject:forced]) return forced;

    NSArray *pref = [NSLocale preferredLanguages];
    for (NSString *tag in pref) {
        if ([supported containsObject:tag]) return tag;
        NSString *prim = [tag componentsSeparatedByString:@"-"].firstObject;
        if ([supported containsObject:prim]) return prim;
        if ([tag hasPrefix:@"zh"] && [supported containsObject:@"zh-Hans"]) return @"zh-Hans";
        if ([tag hasPrefix:@"pt"] && [supported containsObject:@"pt-BR"]) return @"pt-BR";
    }
    return @"en";
}

static void ReloadLangBundle(void) {
    if (!gResBundle) gResBundle = LoadResourceBundle();
    NSArray *supported = gResBundle ? [gResBundle localizations] : kLanguages();
    gCurrentLang = PickLanguage(supported);
    NSString *path = [gResBundle pathForResource:gCurrentLang ofType:@"lproj"];
    gLangBundle = path ? [NSBundle bundleWithPath:path] : gResBundle;
}

NSString *L10n(NSString *key) {
    if (!gLangBundle) ReloadLangBundle();
    if (!gLangBundle) return key;
    NSString *s = [gLangBundle localizedStringForKey:key value:key table:nil];
    return s.length ? s : key;
}

void L10nOverrideLanguage(NSString *lang) {
    if (lang.length) [[NSUserDefaults standardUserDefaults] setObject:lang forKey:@"ytmod.language"];
    else             [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ytmod.language"];
    ReloadLangBundle();
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kYTModSettingsChangedNotification object:nil];
}

NSString *L10nCurrentLanguage(void) {
    if (!gCurrentLang) ReloadLangBundle();
    return gCurrentLang ?: @"en";
}

NSArray<NSString *> *L10nAvailableLanguages(void) {
    if (!gResBundle) gResBundle = LoadResourceBundle();
    return gResBundle ? [gResBundle localizations] : kLanguages();
}

NSString *L10nDisplayNameForLanguage(NSString *lang) {
    NSLocale *loc = [NSLocale localeWithLocaleIdentifier:lang];
    NSString *n = [loc localizedStringForLanguageCode:
        [lang componentsSeparatedByString:@"-"].firstObject];
    return n.capitalizedString ?: lang;
}
