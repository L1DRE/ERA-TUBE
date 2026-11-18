// Google sign-in fix for re-signed YouTube: the SSO keychain access group no
// longer matches after sideloading, so point it at the group the new signature
// actually grants. Bundle ID is deliberately not spoofed: doing that globally
// crashed YouTube at launch on iOS 27.

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

// With other Google apps installed, sign-in hands off to them, and Google rejects
// the re-signed app. Answering "not installed" for their URL schemes makes YouTube
// fall back to its in-app web sign-in. Opening those URLs still works.
static BOOL IsGoogleAppScheme(NSString *scheme) {
    NSString *s = scheme.lowercaseString;
    return [s hasPrefix:@"com.google."] || [s hasPrefix:@"googlechrome"] ||
           [s hasPrefix:@"googlegmail"] || [s hasPrefix:@"googleapp"] ||
           [s hasPrefix:@"gsa"] || [s hasPrefix:@"googleaccounts"];
}

%group CanOpenURL
%hook UIApplication
- (BOOL)canOpenURL:(NSURL *)url {
    NSString *scheme = url.scheme ?: @"";
    static NSMutableSet *seen;
    if (!seen) seen = [NSMutableSet set];
    BOOL hide = SettingsEnabled(@"isolateSignIn") && IsGoogleAppScheme(scheme);
    if (seen.count < 60 && ![seen containsObject:scheme]) {
        [seen addObject:scheme];
        YTModLog(@"canOpenURL scheme %@%@", scheme, hide ? @" -> hidden" : @"");
    }
    return hide ? NO : %orig;
}
%end
%end

%ctor {
    if (objc_getClass("SSOKeychainHelper")) %init(KeychainHelper);
    if (objc_getClass("SSOKeychainCore"))   %init(KeychainCore);
    %init(CanOpenURL);
}
