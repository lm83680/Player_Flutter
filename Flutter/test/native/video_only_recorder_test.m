// Run on macOS with:
// clang -fobjc-arc test/native/video_only_recorder_test.m \
//   ios/Classes/player/FTXVideoOnlyRecorder.m -Iios/Classes/player \
//   -framework Foundation -framework AVFoundation -framework CoreVideo \
//   -framework CoreMedia -framework CoreGraphics -o /tmp/video_recorder_test
// /tmp/video_recorder_test
#import "FTXVideoOnlyRecorder.h"
#import <AVFoundation/AVFoundation.h>

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Pump(NSTimeInterval seconds) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static CVPixelBufferRef Frame(size_t width, size_t height) {
    CVPixelBufferRef buffer = NULL;
    Check(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
          (__bridge CFDictionaryRef)@{(id)kCVPixelBufferIOSurfacePropertiesKey: @{}}, &buffer) == kCVReturnSuccess,
          @"create frame");
    CVPixelBufferLockBaseAddress(buffer, 0);
    memset(CVPixelBufferGetBaseAddress(buffer), 160, CVPixelBufferGetBytesPerRow(buffer) * height);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}
static void Run(NSString *directory, NSString *name, BOOL frames, BOOL resize, NSInteger expected) {
    NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingString:@".mp4"]];
    __block NSInteger completions = 0, code = 99, progress = 0;
    NSError *error = nil;
    FTXVideoOnlyRecorder *recorder = [[FTXVideoOnlyRecorder alloc] initWithPath:path interval:1000
        progress:^(NSInteger duration) { Check(duration >= 1000, @"progress uses milliseconds"); progress++; }
        completion:^(NSInteger result) { completions++; code = result; } error:&error];
    Check(recorder != nil, [NSString stringWithFormat:@"create writer: %@", error]);
    if (frames) {
        CVPixelBufferRef buffer = Frame(320, 240);
        for (int i = 0; i < 40; i++) {
            [recorder appendPixelBuffer:buffer rotation:0];
            Pump(1.0 / 30.0);
        }
        CVPixelBufferRelease(buffer);
        if (resize) {
            buffer = Frame(640, 480);
            [recorder appendPixelBuffer:buffer rotation:0];
            CVPixelBufferRelease(buffer);
            Pump(0.1);
        }
    }
    [recorder stop];
    [recorder stop];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (completions == 0 && deadline.timeIntervalSinceNow > 0) Pump(0.02);
    Pump(0.1);
    Check(completions == 1 && code == expected,
          [NSString stringWithFormat:@"%@: one completion with %ld, received %ld (%ld times)", name, expected, code, completions]);
    if (frames) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        Check([asset tracksWithMediaType:AVMediaTypeAudio].count == 0, @"no audio track");
        Check([asset tracksWithMediaType:AVMediaTypeVideo].count == 1, @"one video track");
        Check(CMTimeGetSeconds(asset.duration) > 1.0, @"video preserves elapsed duration");
        Check(progress > 0, @"progress callback delivered");
    } else {
        Check(![NSFileManager.defaultManager fileExistsAtPath:path], @"empty recording removed");
    }
    NSLog(@"PASS: %@", name);
}
int main(void) {
    @autoreleasepool {
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Check([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil], @"create directory");
        Run(directory, @"video_without_audio", YES, NO, 0);
        Run(directory, @"resolution_change", YES, YES, -2);
        Run(directory, @"no_video_frames", NO, NO, -3);
        [NSFileManager.defaultManager removeItemAtPath:directory error:nil];
    }
    return 0;
}
