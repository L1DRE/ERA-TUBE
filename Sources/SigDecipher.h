#import <Foundation/Foundation.h>

@interface SigDecipher : NSObject

// Загружает base.js (один раз, кэш в памяти + /tmp) и подготавливает движок.
+ (void)prepareWithPlayerJsURL:(NSString *)jsURL
                    completion:(void (^)(BOOL ok, NSError *err))completion;

// Расшифровывает signatureCipher-строку (query string:
//   "s=...&sp=sig&url=...") и возвращает готовую URL. nil если движок не готов.
+ (nullable NSString *)resolveSignatureCipher:(NSString *)signatureCipher;

// Добавляет ?sig=... / &n=... к готовому url c полями s / n (throttled URLs).
+ (nullable NSString *)applyNParam:(NSString *)url;

@end
