#import <Foundation/Foundation.h>

@interface Muxer : NSObject

// Склеивает video-only и audio-only файлы в единый .mp4 (passthrough,
// без перекодирования). Работает для H.264+AAC; VP9/Opus iOS не упакует.
+ (void)muxVideo:(NSURL *)videoFile
           audio:(NSURL *)audioFile
       outputURL:(NSURL *)outURL
      completion:(void (^)(BOOL ok, NSError *err))completion;

@end
