// Google sign-in fix for re-signed YouTube.
// After sideloading, the bundle ID and keychain access group no longer match
// what Google's SSO expects, so sign-in is rejected as an unverified app.

#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString *const kYouTubeBundleID = @"com.google.ios.youtube";

// The access group the new signature actually grants; read back from a probe item.
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

%hook SSOKeychainHelper
+ (NSString *)accessGroup       { return KeychainAccessGroup() ?: %orig; }
+ (NSString *)sharedAccessGroup { return KeychainAccessGroup() ?: %orig; }
%end

%hook SSOKeychainCore
+ (NSString *)accessGroup       { return KeychainAccessGroup() ?: %orig; }
+ (NSString *)sharedAccessGroup { return KeychainAccessGroup() ?: %orig; }
%end

%hook NSBundle
- (NSString *)bundleIdentifier {
    return self == NSBundle.mainBundle ? kYouTubeBundleID : %orig;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (self == NSBundle.mainBundle && [key isEqualToString:@"CFBundleIdentifier"])
        return kYouTubeBundleID;
    return %orig;
}
%end
