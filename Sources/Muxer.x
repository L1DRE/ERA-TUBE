#import "Muxer.h"
#import <AVFoundation/AVFoundation.h>

@implementation Muxer

+ (void)muxVideo:(NSURL *)videoFile
           audio:(NSURL *)audioFile
       outputURL:(NSURL *)outURL
      completion:(void (^)(BOOL, NSError *))completion {

    AVURLAsset *vAsset = [AVURLAsset assetWithURL:videoFile];
    AVURLAsset *aAsset = [AVURLAsset assetWithURL:audioFile];

    AVAssetTrack *vTrack = [[vAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    AVAssetTrack *aTrack = [[aAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!vTrack || !aTrack) {
        completion(NO, [NSError errorWithDomain:@"Muxer" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"missing tracks (unsupported codec?)"}]);
        return;
    }

    AVMutableComposition *comp = [AVMutableComposition composition];
    AVMutableCompositionTrack *cv = [comp addMutableTrackWithMediaType:AVMediaTypeVideo
                                                      preferredTrackID:kCMPersistentTrackID_Invalid];
    AVMutableCompositionTrack *ca = [comp addMutableTrackWithMediaType:AVMediaTypeAudio
                                                      preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *err = nil;
    CMTimeRange vRange = CMTimeRangeMake(kCMTimeZero, vAsset.duration);
    [cv insertTimeRange:vRange ofTrack:vTrack atTime:kCMTimeZero error:&err];
    if (err) { completion(NO, err); return; }

    CMTime audioDur = CMTimeMinimum(aAsset.duration, vAsset.duration);
    [ca insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioDur)
                ofTrack:aTrack atTime:kCMTimeZero error:&err];
    if (err) { completion(NO, err); return; }

    cv.preferredTransform = vTrack.preferredTransform;

    AVAssetExportSession *ex = [[AVAssetExportSession alloc]
        initWithAsset:comp presetName:AVAssetExportPresetPassthrough];
    ex.outputFileType = AVFileTypeMPEG4;
    [NSFileManager.defaultManager removeItemAtURL:outURL error:nil];
    ex.outputURL = outURL;
    ex.shouldOptimizeForNetworkUse = YES;
    [ex exportAsynchronouslyWithCompletionHandler:^{
        BOOL ok = ex.status == AVAssetExportSessionStatusCompleted;
        completion(ok, ex.error);
    }];
}

@end
