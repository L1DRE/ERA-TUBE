#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { const char *key; const char *title; const char *section; } YTModOption;
extern const YTModOption kYTModOptions[];
extern const NSInteger   kYTModOptionCount;

void      SettingsLoad(void);
BOOL      SettingsEnabled(NSString *key);
void      SettingsSetEnabled(NSString *key, BOOL value);
NSArray * SettingsOrderedSections(void);
NSArray * SettingsKeysForSection(NSString *section);
NSString *SettingsTitleForKey(NSString *key);
NSString *SettingsLocalizedSection(NSString *section);

extern NSString *const kYTModSettingsChangedNotification;

#ifdef __cplusplus
}
#endif
