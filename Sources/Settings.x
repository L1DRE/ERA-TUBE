#import "Settings.h"
#import "L10n.h"

NSString *const kYTModSettingsChangedNotification = @"com.ytmod.settingsChanged";

static NSMutableDictionary *gDefaults;

static NSString *PrefsPath(void) {
    // В sideload-IPA /var/mobile пустой/недоступный. Пишем в Documents app'а.
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = dirs.firstObject ?: NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"ytmod.plist"];
}

// ---- каталог опций (ключ, заголовок, секция) ----
const YTModOption kYTModOptions[] = {
    {"adsOff",       "Block ads in feed",         "Ads"},
    {"videoAdsOff",  "Block ads in videos",       "Ads"},
    {"hideBranding", "Hide branding overlays",    "Ads"},
    {"background",   "Background playback",       "Playback"},
    {"pip",          "Picture-in-Picture",        "Playback"},
    {"sponsorBlock", "Skip sponsor segments",     "Playback"},
    {"sponsorBlockExtra", "Also skip intros, outros, previews and filler", "Playback"},
    {"hideShorts",   "Hide Shorts tab",           "UI"},
    {"downloader",   "Downloader button",         "Downloader"},
    {"spoofBundleID", "Fix Google sign-in (experimental)", "Account"},
};
const NSInteger kYTModOptionCount =
    sizeof(kYTModOptions) / sizeof(kYTModOptions[0]);

void SettingsLoad(void) {
    gDefaults = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < kYTModOptionCount; i++) {
        NSString *k = @(kYTModOptions[i].key);
        BOOL def = !([k isEqualToString:@"hideShorts"] ||
                     [k isEqualToString:@"hideBranding"] ||
                     [k isEqualToString:@"spoofBundleID"]);
        gDefaults[k] = @(def);
    }
    NSDictionary *user = [NSDictionary dictionaryWithContentsOfFile:PrefsPath()];
    if (user) [gDefaults addEntriesFromDictionary:user];
}

static void SettingsSave(void) {
    [gDefaults writeToFile:PrefsPath() atomically:YES];
}

BOOL SettingsEnabled(NSString *key) {
    id v = gDefaults[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : NO;
}

void SettingsSetEnabled(NSString *key, BOOL value) {
    gDefaults[key] = @(value);
    SettingsSave();
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kYTModSettingsChangedNotification object:nil];
}

NSArray *SettingsOrderedSections(void) {
    NSMutableArray *order = [NSMutableArray array];
    for (NSInteger i = 0; i < kYTModOptionCount; i++) {
        NSString *s = @(kYTModOptions[i].section);
        if (![order containsObject:s]) [order addObject:s];
    }
    return order;
}

NSArray *SettingsKeysForSection(NSString *section) {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSInteger i = 0; i < kYTModOptionCount; i++) {
        if ([@(kYTModOptions[i].section) isEqualToString:section])
            [keys addObject:@(kYTModOptions[i].key)];
    }
    return keys;
}

NSString *SettingsTitleForKey(NSString *key) {
    for (NSInteger i = 0; i < kYTModOptionCount; i++) {
        if ([@(kYTModOptions[i].key) isEqualToString:key])
            return L10n(@(kYTModOptions[i].title));
    }
    return key;
}

NSString *SettingsLocalizedSection(NSString *section) { return L10n(section); }
