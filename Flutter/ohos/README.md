# SuperPlayer OpenHarmony integration

This directory is the OpenHarmony plugin entry point for `super_player`.

The Tencent LiteAV Professional 13.2.0.8729 HAR and Flutter engine HAR are
vendored in `har/`. Applications must declare `ohos.permission.INTERNET` (and
network-info permissions when required) in `entry/src/main/module.json5`.

The Flutter side registers `FTXRenderViewType` as an `OhosView`. The native
view creates a LiteAV XComponent and binds the player using that component's
unique id, matching the existing `TXPlayerVideo`/`setPlayerView` contract.

## Native SDK dependency

The plugin currently supports live playback and player lifecycle/event
callbacks through the bundled LiteAV SDK. VOD playback and unsupported native
operations remain unavailable on OpenHarmony.

## Video-only recording

`FTXLiveLocalRecordingParams(recordMode: FTXLiveRecordMode.videoOnly)` uses a
video-only system AVRecorder on API 12+. The bundled LiteAV HAR has no decoded
video observer, so this mode samples original SDK video snapshots at up to 15 fps.
Actual frame rate depends on snapshot and encoder throughput. No screen capture
or microphone permission is required. A small CMake/N-API module copies RGBA/BGRA
snapshots into the recorder's input Surface. Keep playback running, and wait for
`recordCompleteCallback` before reading the MP4 or starting another recording.
A five-second gap without a writable video frame ends the recording.
