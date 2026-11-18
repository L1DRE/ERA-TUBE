// Google sign-in fix for re-signed YouTube: the SSO keychain access group no
// longer matches after sideloading, so point it at the group the new signature
// actually grants.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Settings.h"
#import "Diagnostics.h"

static NSString *KeychainAccessGroup(void) {
    static NSString *group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *q = @{
            (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount:      @"ytmod.bundleSeedID",
            (__bridge id)kSecAttrService:      @"ytmod",
            (__bridge id)kSecReturnAttributes: @YES,
        };
        CFTypeRef res = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &res);
        if (st == errSecItemNotFound) st = SecItemAdd((__bridge CFDictionaryRef)q, &res);
        if (st == errSecSuccess && res) {
            NSDictionary *attrs = (__bridge_transfer NSDictionary *)res;
            group = [attrs[(__bridge id)kSecAttrAccessGroup] copy];
        }
    });
    return group;
}

%group KeychainHelper
%hook SSOKeychainHelper
+ (NSString *)accessGroup       { return KeychainAccessGroup() ?: %orig; }
+ (NSString *)sharedAccessGroup { return KeychainAccessGroup() ?: %orig; }
%end
%end

%group KeychainCore
%hook SSOKeychainCore
+ (NSString *)accessGroup       { return KeychainAccessGroup() ?: %orig; }
+ (NSString *)sharedAccessGroup { return KeychainAccessGroup() ?: %orig; }
%end
%end

// Experimental: report the original bundle ID, which Google's web sign-in checks.
// Spoofing from launch aborted YouTube in its initializers on iOS 27, so the spoof
// only arms a few seconds after launch, once startup code has read the real ID.
static NSString *const kYouTubeBundleID = @"com.google.ios.youtube";
static BOOL gSpoofArmed;

%group BundleSpoof
%hook NSBundle
- (NSString *)bundleIdentifier {
    return (gSpoofArmed && self == NSBundle.mainBundle) ? kYouTubeBundleID : %orig;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (gSpoofArmed && self == NSBundle.mainBundle && [key isEqualToString:@"CFBundleIdentifier"])
        return kYouTubeBundleID;
    return %orig;
}
%end
%end

%ctor {
    if (objc_getClass("SSOKeychainHelper")) %init(KeychainHelper);
    if (objc_getClass("SSOKeychainCore"))   %init(KeychainCore);
    %init(BundleSpoof);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!SettingsEnabled(@"spoofBundleID")) return;
        gSpoofArmed = YES;
        YTModLog(@"sign-in fix: bundle ID spoof armed");
    });
}
