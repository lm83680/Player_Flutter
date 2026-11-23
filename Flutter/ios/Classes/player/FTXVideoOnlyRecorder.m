// Copyright (c) 2026 Tencent. All rights reserved.
#import "FTXVideoOnlyRecorder.h"
#import <AVFoundation/AVFoundation.h>

@implementation FTXVideoOnlyRecorder {
    NSString *_path;
    NSInteger _interval;
    void (^_progress)(NSInteger);
    void (^_completion)(NSInteger);
    dispatch_queue_t _queue;
    AVAssetWriter *_writer;
    AVAssetWriterInput *_input;
    AVAssetWriterInputPixelBufferAdaptor *_adaptor;
    BOOL _stopping;
    BOOL _framePending;
    BOOL _finishing;
    NSInteger _width;
    NSInteger _height;
    NSInteger _rotation;
    NSInteger _samples;
    NSInteger _lastProgress;
    CMTime _firstTime;
    CMTime _lastPTS;
}

- (instancetype)initWithPath:(NSString *)path interval:(NSInteger)interval
                   progress:(void (^)(NSInteger))progress
                 completion:(void (^)(NSInteger))completion error:(NSError **)error {
    if ((self = [super init])) {
        _path = [path copy];
        _interval = interval >= 1000 && interval <= 10000 ? interval : -1;
        _progress = [progress copy];
        _completion = [completion copy];
        _queue = dispatch_queue_create("com.tencent.superplayer.video-recording", DISPATCH_QUEUE_SERIAL);
        _lastPTS = kCMTimeInvalid;
        _writer = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:path]
                                          fileType:AVFileTypeMPEG4 error:error];
        if (!_writer) return nil;
    }
    return self;
}

- (void)appendPixelBuffer:(CVPixelBufferRef)pixelBuffer rotation:(NSInteger)rotation {
    if (!pixelBuffer) return;
    CMTime now = CMClockGetTime(CMClockGetHostTimeClock());
    @synchronized (self) {
        if (_stopping || _framePending) return;
        _framePending = YES;
        CVPixelBufferRetain(pixelBuffer);
        dispatch_async(_queue, ^{
            @try {
                if (!self->_finishing) [self encodePixelBuffer:pixelBuffer rotation:rotation time:now];
            } @finally {
                CVPixelBufferRelease(pixelBuffer);
                @synchronized (self) { self->_framePending = NO; }
            }
        });
    }
}

- (void)encodePixelBuffer:(CVPixelBufferRef)buffer rotation:(NSInteger)rotation time:(CMTime)now {
    NSInteger width = CVPixelBufferGetWidth(buffer);
    NSInteger height = CVPixelBufferGetHeight(buffer);
    if (!_input) {
        _width = width;
        _height = height;
        _rotation = rotation;
        NSDictionary *settings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(width), AVVideoHeightKey: @(height),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(MIN(12000000, MAX(1000000, width * height * 4))),
                AVVideoMaxKeyFrameIntervalKey: @60
            }
        };
        _input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
        _input.expectsMediaDataInRealTime = YES;
        _input.transform = CGAffineTransformMakeRotation(rotation * M_PI_2);
        _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_input
                                                                                   sourcePixelBufferAttributes:nil];
        if (![_writer canAddInput:_input]) { [self finish:-1]; return; }
        [_writer addInput:_input];
        if (![_writer startWriting]) { [self finish:-1]; return; }
        [_writer startSessionAtSourceTime:kCMTimeZero];
        _firstTime = now;
    } else if (_width != width || _height != height || _rotation != rotation) {
        [self finish:-2];
        return;
    }
    if (!_input.readyForMoreMediaData) return;
    CMTime pts = CMTimeSubtract(now, _firstTime);
    if (CMTIME_IS_VALID(_lastPTS) && CMTimeCompare(pts, _lastPTS) <= 0) {
        pts = CMTimeAdd(_lastPTS, CMTimeMake(1, 1000000));
    }
    if (![_adaptor appendPixelBuffer:buffer withPresentationTime:pts]) { [self finish:-1]; return; }
    _lastPTS = pts;
    _samples++;
    NSInteger duration = (NSInteger)(CMTimeGetSeconds(pts) * 1000);
    if (_interval > 0 && duration - _lastProgress >= _interval) {
        _lastProgress = duration;
        void (^callback)(NSInteger) = _progress;
        dispatch_async(dispatch_get_main_queue(), ^{ callback(duration); });
    }
}

- (void)stop {
    @synchronized (self) {
        if (_stopping) return;
        _stopping = YES;
        dispatch_async(_queue, ^{ [self finish:0]; });
    }
}

- (void)finish:(NSInteger)code {
    if (_finishing) return;
    _finishing = YES;
    @synchronized (self) { _stopping = YES; }
    if (_samples == 0 || code == -1 || _writer.status != AVAssetWriterStatusWriting) {
        [_writer cancelWriting];
        [self completed:code == 0 ? -3 : code];
        return;
    }
    [_input markAsFinished];
    // End on a frame boundary instead of leaving the final sample at zero duration.
    [_writer endSessionAtSourceTime:CMTimeAdd(_lastPTS, CMTimeMake(1, 30))];
    [_writer finishWritingWithCompletionHandler:^{
        [self completed:self->_writer.status == AVAssetWriterStatusCompleted ? code : -1];
    }];
}

- (void)completed:(NSInteger)code {
    if (code == -1 || _samples == 0) [[NSFileManager defaultManager] removeItemAtPath:_path error:nil];
    void (^callback)(NSInteger) = _completion;
    dispatch_async(dispatch_get_main_queue(), ^{ callback(code); });
}
@end
