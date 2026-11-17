#import <Foundation/Foundation.h>

// Возвращает локализованную строку из нашего бандла YTModResources.bundle.
// Если ключа нет — возвращает сам ключ, чтобы UI не падал.
NSString *L10n(NSString *key);

// Явно сменить язык (BCP-47, напр. "ru", "kk", "zh-Hans"); nil = системный.
void L10nOverrideLanguage(NSString *lang);
NSString *L10nCurrentLanguage(void);
NSArray<NSString *> *L10nAvailableLanguages(void);
NSString *L10nDisplayNameForLanguage(NSString *lang);
