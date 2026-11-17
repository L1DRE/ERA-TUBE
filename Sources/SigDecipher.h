#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SigDecipher : NSObject

// Загружает base.js (один раз, кэш в памяти) и подготавливает движок.
+ (void)prepareWithPlayerJsURL:(nullable NSString *)jsURL
                    completion:(void (^)(BOOL ok, NSError * _Nullable err))completion;

// Расшифровывает signatureCipher-строку (query string:
//   "s=...&sp=sig&url=...") и возвращает готовую URL. nil если движок не готов.
+ (nullable NSString *)resolveSignatureCipher:(NSString *)signatureCipher;

// Пересчитывает параметр n (анти-троттлинг) в готовой URL.
+ (nullable NSString *)applyNParam:(NSString *)url;

@end

NS_ASSUME_NONNULL_END
