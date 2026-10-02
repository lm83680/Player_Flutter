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
