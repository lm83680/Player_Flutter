// Copyright (c) 2026 Tencent. All rights reserved.
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// A bounded, serial AVAssetWriter pipeline with a single H.264 video input.
@interface FTXVideoOnlyRecorder : NSObject
- (nullable instancetype)initWithPath:(NSString *)path
                            interval:(NSInteger)interval
                            progress:(void (^)(NSInteger durationMs))progress
                          completion:(void (^)(NSInteger code))completion
                               error:(NSError **)error;
- (void)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer rotation:(NSInteger)rotation;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
