// Copyright (c) 2026 Tencent. All rights reserved.
import media from '@ohos.multimedia.media';
import image from '@ohos.multimedia.image';
import fs from '@ohos.file.fs';
import systemDateTime from '@ohos.systemDateTime';
import { createOutput, openSurface, writeFrame, closeSurface } from 'libsuperplayer_recorder.so';

export class VideoRecordingCallbacks {
  progress: (durationMs: number) => void;
  complete: (code: number) => void;
  constructor(progress: (durationMs: number) => void, complete: (code: number) => void) {
    this.progress = progress;
    this.complete = complete;
  }
}

/** The bundled LiteAV HAR exposes snapshots, but no decoded-video observer.
 * Sample its original video snapshots at up to 15 fps into a video-only AVRecorder.
 * There is at most one SDK snapshot and one PixelMap operation in flight.
 */
export class VideoOnlyRecorder {
  private path: string;
  private fd: number;
  private interval: number;
  private callbacks: VideoRecordingCallbacks;
  private requestSnapshot: () => boolean;
  private recorder: media.AVRecorder | null = null;
  private surface: number = -1;
  private width: number = 0;
  private height: number = 0;
  private frames: number = 0;
  private firstFrameMs: number = 0;
  private lastProgressMs: number = 0;
  private lastFrameMs: number = 0;
  private timer: number = -1;
  private watchdog: number = -1;
  private stopping: boolean = false;
  private work: Promise<void> = Promise.resolve();
  private stopWork: Promise<void> | null = null;

  static createFile(path: string): number {
    if (!path.toLowerCase().endsWith('.mp4')) return -2;
    return createOutput(path);
  }

  constructor(path: string, fd: number, interval: number, requestSnapshot: () => boolean,
    callbacks: VideoRecordingCallbacks) {
    this.path = path;
    this.fd = fd;
    this.interval = interval >= 1000 && interval <= 10000 ? interval : -1;
    this.requestSnapshot = requestSnapshot;
    this.callbacks = callbacks;
  }

  start(): void {
    this.lastFrameMs = this.now();
    this.watchdog = setInterval(() => {
      if (this.now() - this.lastFrameMs > 5000) this.stop(this.frames === 0 ? -3 : -1);
    }, 1000);
    this.schedule();
  }

  private now(): number { return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, false); }

  private schedule(): void {
    if (this.stopping) return;
    this.timer = setTimeout(() => {
      this.timer = -1;
      // A user snapshot may already be in flight. Retry without adding a queue.
      if (!this.requestSnapshot()) this.schedule();
    }, 67);
  }

  appendSnapshot(pixelMap: image.PixelMap): void {
    // Keep the PixelMap until all async reads are finished, including during stop.
    this.work = this.work.then(async () => {
      try {
        if (this.stopping) return;
        const info = await pixelMap.getImageInfo();
        if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
          info.pixelFormat !== image.PixelMapFormat.BGRA_8888) throw new Error('Unsupported snapshot pixel format');
        if (this.recorder === null) await this.prepare(info.size.width, info.size.height);
        else if (this.width !== info.size.width || this.height !== info.size.height) {
          this.stop(-2);
          return;
        }
        if (this.stopping) return;
        const stride = pixelMap.getBytesNumberPerRow();
        const data = new ArrayBuffer(stride * this.height);
        await pixelMap.readPixelsToBuffer(data);
        if (this.stopping) return;
        if (!writeFrame(this.surface, data, stride, info.pixelFormat === image.PixelMapFormat.BGRA_8888)) {
          // Encoder backpressure drops a frame; the watchdog detects persistent failure.
          return;
        }
        const now = this.now();
        if (this.frames === 0) this.firstFrameMs = now;
        this.lastFrameMs = now;
        this.frames++;
        const duration = now - this.firstFrameMs;
        if (this.interval > 0 && duration - this.lastProgressMs >= this.interval) {
          this.lastProgressMs = duration;
          this.callbacks.progress(duration);
        }
      } catch (_error) {
        this.stop(-1);
      } finally {
        try { await pixelMap.release(); } catch (_error) {}
        this.schedule();
      }
    });
  }

  private async prepare(width: number, height: number): Promise<void> {
    this.width = width;
    this.height = height;
    this.recorder = await media.createAVRecorder();
    this.recorder.on('error', () => { this.stop(-1); });
    const profile: media.AVRecorderProfile = {
      fileFormat: media.ContainerFormatType.CFT_MPEG_4,
      videoCodec: media.CodecMimeType.VIDEO_AVC,
      videoBitrate: Math.min(12000000, Math.max(1000000, width * height * 4)),
      videoFrameWidth: width,
      videoFrameHeight: height,
      videoFrameRate: 15
    };
    // Omitting audioSourceType is what makes this a video-only recording.
    const config: media.AVRecorderConfig = {
      videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
      profile: profile,
      url: `fd://${this.fd}`
    };
    await this.recorder.prepare(config);
    this.surface = openSurface(await this.recorder.getInputSurface(), width, height);
    if (this.surface < 0) throw new Error('Unable to open recording surface');
    await this.recorder.start();
  }

  stop(code: number = 0): Promise<void> {
    if (this.stopWork !== null) return this.stopWork;
    this.stopping = true;
    if (this.timer >= 0) clearTimeout(this.timer);
    if (this.watchdog >= 0) clearInterval(this.watchdog);
    // No waiting for the next snapshot callback: it may never arrive after stopPlay.
    this.stopWork = this.work.then(() => this.finish(code));
    return this.stopWork;
  }

  private async finish(code: number): Promise<void> {
    let result = code;
    try {
      if (this.surface >= 0) { closeSurface(this.surface); this.surface = -1; }
      if (this.recorder !== null && this.recorder.state === 'started') await this.recorder.stop();
      if (result === 0 && this.frames === 0) result = -3;
    } catch (_error) {
      result = this.frames === 0 && code === 0 ? -3 : -1;
    } finally {
      if (this.recorder !== null) {
        try { await this.recorder.release(); } catch (_error) { result = -1; }
        this.recorder = null;
      }
      try { fs.closeSync(this.fd); } catch (_error) { result = -1; }
      if (result === -1 || this.frames === 0) {
        try { fs.unlinkSync(this.path); } catch (_error) {}
      }
    }
    this.callbacks.complete(result);
  }
}
