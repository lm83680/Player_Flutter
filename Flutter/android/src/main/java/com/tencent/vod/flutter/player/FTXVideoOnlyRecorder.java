// Copyright (c) 2026 Tencent. All rights reserved.
package com.tencent.vod.flutter.player;

import android.graphics.Bitmap;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Encodes SDK video snapshots into an MP4 containing one H.264 track. */
final class FTXVideoOnlyRecorder {
    interface Listener {
        void onProgress(long durationMs);
        void onComplete(int code);
    }

    private final File file;
    private final int interval;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private boolean stopping;
    private boolean framePending;
    // The remaining fields are confined to worker.
    private MediaCodec encoder;
    private MediaMuxer muxer;
    private boolean muxerStarted;
    private int track;
    private int width;
    private int height;
    private int rotation;
    private boolean semiPlanar;
    private long firstFrameNs;
    private long lastPtsUs = -1;
    private long lastProgressMs;
    private int samples;
    private boolean finished;

    FTXVideoOnlyRecorder(String path, int interval, Listener listener) throws IOException {
        file = new File(path);
        if (!file.createNewFile()) throw new IOException("Recording file already exists");
        this.interval = interval >= 1000 && interval <= 10000 ? interval : -1;
        this.listener = listener;
    }

    synchronized void append(Bitmap bitmap) {
        // The SDK owns the bitmap; copy its pixels before returning from its callback.
        if (stopping || framePending || bitmap == null) return;
        int width = bitmap.getWidth();
        int height = bitmap.getHeight();
        if (width <= 0 || height <= 0 || (width & 1) != 0 || (height & 1) != 0
                || (long) width * height > Integer.MAX_VALUE / 4) {
            stopWithCode(-1);
            return;
        }
        int[] pixels = new int[width * height];
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height);
        long now = System.nanoTime();
        framePending = true;
        worker.execute(() -> {
            try {
                if (!finished) encode(toI420(pixels, width, height), width, height, 0, now);
            } catch (Exception e) {
                finish(-1);
            } finally {
                synchronized (FTXVideoOnlyRecorder.this) { framePending = false; }
            }
        });
    }

    private static byte[] toI420(int[] pixels, int width, int height) {
        int count = width * height;
        byte[] data = new byte[count * 3 / 2];
        int uIndex = count, vIndex = count + count / 4;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int rgb = pixels[y * width + x];
                int r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
                data[y * width + x] = (byte) Math.max(0, Math.min(255, ((66*r + 129*g + 25*b + 128) >> 8) + 16));
                if ((y & 1) == 0 && (x & 1) == 0) {
                    data[uIndex++] = (byte) Math.max(0, Math.min(255, ((-38*r - 74*g + 112*b + 128) >> 8) + 128));
                    data[vIndex++] = (byte) Math.max(0, Math.min(255, ((112*r - 94*g - 18*b + 128) >> 8) + 128));
                }
            }
        }
        return data;
    }

    synchronized void stop() { stopWithCode(0); }

    private synchronized void stopWithCode(int code) {
        if (stopping) return;
        stopping = true;
        worker.execute(() -> finish(code));
    }

    private void prepare(int width, int height, int rotation) throws IOException {
        this.width = width;
        this.height = height;
        this.rotation = rotation;
        // Use a concrete byte-buffer layout, including on API 19/20 devices.
        MediaCodecInfo selected = null;
        int color = 0;
        for (int i = 0; i < MediaCodecList.getCodecCount() && selected == null; i++) {
            MediaCodecInfo info = MediaCodecList.getCodecInfoAt(i);
            if (!info.isEncoder()) continue;
            for (String type : info.getSupportedTypes()) {
                if (!"video/avc".equalsIgnoreCase(type)) continue;
                for (int candidate : info.getCapabilitiesForType(type).colorFormats) {
                    if (candidate == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
                            || candidate == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar) {
                        selected = info;
                        color = candidate;
                        break;
                    }
                }
            }
        }
        if (selected == null) throw new IOException("No byte-buffer H.264 encoder available");
        semiPlanar = color == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar;
        MediaFormat format = MediaFormat.createVideoFormat("video/avc", width, height);
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, color);
        format.setInteger(MediaFormat.KEY_BIT_RATE, (int) Math.min(12000000L, Math.max(1000000L, (long) width * height * 4)));
        format.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2);
        encoder = MediaCodec.createByCodecName(selected.getName());
        encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
        encoder.start();
        muxer = new MediaMuxer(file.getAbsolutePath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        muxer.setOrientationHint(rotation);
    }

    private void encode(byte[] data, int w, int h, int r, long now) throws IOException {
        if (encoder == null) {
            prepare(w, h, r);
            firstFrameNs = now;
        } else if (width != w || height != h || rotation != r) {
            finish(-2);
            return;
        }
        drain(false);
        int index = encoder.dequeueInputBuffer(0);
        if (index < 0) return;
        ByteBuffer input = encoder.getInputBuffers()[index];
        input.clear();
        int pixels = width * height;
        int size = pixels * 3 / 2;
        if (input.remaining() < size) throw new IOException("Encoder input buffer too small");
        input.put(data, 0, pixels);
        if (semiPlanar) {
            for (int i = 0; i < pixels / 4; i++) {
                input.put(data[pixels + i]);
                input.put(data[pixels + pixels / 4 + i]);
            }
        } else {
            input.put(data, pixels, pixels / 2);
        }
        long pts = Math.max(lastPtsUs + 1, (now - firstFrameNs) / 1000);
        encoder.queueInputBuffer(index, 0, size, pts, 0);
        lastPtsUs = pts;
        drain(false);
        long durationMs = pts / 1000;
        if (interval > 0 && durationMs - lastProgressMs >= interval) {
            lastProgressMs = durationMs;
            main.post(() -> listener.onProgress(durationMs));
        }
    }

    private void drain(boolean eos) throws IOException {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        long deadline = System.nanoTime() + 3000000000L;
        while (true) {
            int index = encoder.dequeueOutputBuffer(info, eos ? 10000 : 0);
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!eos) return;
                if (System.nanoTime() >= deadline) throw new IOException("Encoder EOS timed out");
            } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (muxerStarted) throw new IOException("Encoder format changed");
                track = muxer.addTrack(encoder.getOutputFormat());
                muxer.start();
                muxerStarted = true;
            } else if (index >= 0) {
                try {
                    if ((info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0 && info.size > 0) {
                        if (!muxerStarted) throw new IOException("Encoder has no output format");
                        ByteBuffer output = encoder.getOutputBuffers()[index];
                        output.position(info.offset);
                        output.limit(info.offset + info.size);
                        muxer.writeSampleData(track, output, info);
                        samples++;
                    }
                } finally {
                    encoder.releaseOutputBuffer(index, false);
                }
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
            }
            if (eos && System.nanoTime() >= deadline) throw new IOException("Encoder EOS timed out");
        }
    }

    private void finish(int code) {
        if (finished) return;
        finished = true;
        synchronized (this) { stopping = true; }
        try {
            if (encoder != null && code != -1) {
                long deadline = System.nanoTime() + 3000000000L;
                int index;
                while ((index = encoder.dequeueInputBuffer(10000)) < 0) {
                    drain(false);
                    if (System.nanoTime() >= deadline) throw new IOException("Encoder input timed out");
                }
                encoder.queueInputBuffer(index, 0, 0, Math.max(0, lastPtsUs + 1), MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                drain(true);
            }
            if (muxerStarted) muxer.stop();
            if (samples == 0 && code == 0) code = -3;
        } catch (Exception e) {
            code = -1;
        } finally {
            if (encoder != null) {
                try { encoder.stop(); } catch (Exception ignored) { }
                try { encoder.release(); } catch (Exception ignored) { }
            }
            if (muxer != null) {
                try { muxer.release(); } catch (Exception ignored) { }
            }
            if (code == -1 || samples == 0) file.delete();
            worker.shutdown();
        }
        final int result = code;
        main.post(() -> listener.onComplete(result));
    }
}
