import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { ITXVodPlayCallback, TXVodDef, TXVodPlayConfig, TXVodPlayer, V2TXLivePlayer, V2TXLivePlayerObserver, V2TXLivePlayerStatistics, V2TXLivePremier, V2TXLiveLogConfig, V2TXLiveLogLevel, createV2TXLivePlayer, releaseV2TXLivePlayer, getV2TXLivePremierShareInstance, V2TXLiveFillMode, V2TXLiveLocalRecordingParams, V2TXLiveRecordMode, V2TXLiveProperty } from 'liteavsdk';
import common from '@ohos.app.ability.common';
import image from '@ohos.multimedia.image';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';

const PREFIX = 'dev.flutter.pigeon.super_player.';
const VIEW_TYPE = 'FTXRenderViewType';
class Codec extends StandardMessageCodec {
  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof PlayerMsg) { stream.writeUint8(129); return this.writeValue(stream, [value.playerId]); }
    if (value instanceof VodPlayConfigMsg) { stream.writeUint8(139); return this.writeValue(stream, value.values); }
    if (value instanceof BoolMsg) { stream.writeUint8(145); return this.writeValue(stream, [value.value]); }
    if (value instanceof IntMsg) { stream.writeUint8(146); return this.writeValue(stream, [value.value]); }
    if (value instanceof StringMsg) { stream.writeUint8(147); return this.writeValue(stream, [value.value]); }
    if (value instanceof DoubleMsg) { stream.writeUint8(149); return this.writeValue(stream, [value.value]); }
    return super.writeValue(stream, value);
  }
  readValueOfType(type: number, buffer: ByteBuffer): ESObject {
    switch (type) {
      case 129:
        return new PlayerMsg((this.readValue(buffer) as Array<Object>)[0] as number);
      case 130: {
        const value = this.readValue(buffer) as Array<Object>;
        return new LicenseMessage(value[0] as string, value[1] as string);
      }
      case 135: {
        const value = this.readValue(buffer) as Array<Object>;
        return new BoolMsg(value[1] as boolean, value[0] as number);
      }
      case 136: {
        const value = this.readValue(buffer) as Array<Object>;
        return new StringMsg(value[1] as string, value[0] as number);
      }
      case 137: {
        const value = this.readValue(buffer) as Array<Object>;
        return new DoubleMsg(value[1] as number, value[0] as number);
      }
      case 139:
        return new VodPlayConfigMsg(this.readValue(buffer) as Array<ESObject>);
      case 145:
        return new BoolMsg((this.readValue(buffer) as Array<Object>)[0] as boolean);
      case 146:
        return new IntMsg((this.readValue(buffer) as Array<Object>)[0] as number);
      case 147:
        return new StringMsg((this.readValue(buffer) as Array<Object>)[0] as string);
      case 149:
        return new DoubleMsg((this.readValue(buffer) as Array<Object>)[0] as number);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}
class PlayerMsg {
  playerId: number;
  constructor(playerId: number) { this.playerId = playerId; }
}
class BoolMsg {
  value: boolean;
  playerId?: number;
  constructor(value: boolean, playerId?: number) { this.value = value; this.playerId = playerId; }
}
class IntMsg {
  value: number;
  constructor(value: number) { this.value = value; }
}
class DoubleMsg {
  value: number;
  playerId?: number;
  constructor(value: number, playerId?: number) { this.value = value; this.playerId = playerId; }
}
class StringMsg {
  value: string;
  playerId?: number;
  constructor(value: string, playerId?: number) { this.value = value; this.playerId = playerId; }
}
class LicenseMessage {
  licenseUrl: string;
  licenseKey: string;
  constructor(licenseUrl: string, licenseKey: string) { this.licenseUrl = licenseUrl; this.licenseKey = licenseKey; }
}
class VodPlayConfigMsg {
  values: Array<ESObject>;
  constructor(values: Array<ESObject>) { this.values = values; }
}
const codec = new Codec();
const players = new Map<number, LivePlayer>();
const vodPlayers = new Map<number, VodPlayer>();
interface RenderTarget {
  componentId: string;
  surfaceId: string;
}
const renderTargets = new Map<number, RenderTarget>();
let livePremier: V2TXLivePremier | null = null;
let liveLogConfig: V2TXLiveLogConfig | null = null;
let nextId = 1;

class LivePlayer {
  player: V2TXLivePlayer;
  id: number;
  renderViewId?: number;
  isMuted: boolean = false;
  isPaused: boolean = false;
  constructor(id: number, context: common.Context, messenger: BinaryMessenger) {
    this.id = id;
    this.player = createV2TXLivePlayer(context);
    const observer: V2TXLivePlayerObserver = new LivePlayerObserver(this, messenger);
    this.player.setObserver(observer);
  }
  startPlay(url: string): number {
    this.isPaused = false;
    this.player.resumeVideo();
    if (!this.isMuted) this.player.resumeAudio();
    return this.player.startPlay(url);
  }
  stopPlay(): number {
    this.isPaused = false;
    return this.player.stopPlay();
  }
  pause(): void {
    this.player.pauseVideo();
    this.player.pauseAudio();
    this.isPaused = true;
  }
  resume(): void {
    this.player.resumeVideo();
    if (!this.isMuted) this.player.resumeAudio();
    this.isPaused = false;
  }
  setMute(mute: boolean): void {
    this.isMuted = mute;
    if (mute) this.player.pauseAudio();
    else if (!this.isPaused) this.player.resumeAudio();
  }
  event(messenger: BinaryMessenger, method: string, args: Map<string, Object>): void {
    const channel = new BasicMessageChannel<Object>(messenger, `${PREFIX}TXLivePlayerFlutterAPI.${method}.${this.id}`, codec);
    channel.send([args]);
  }
  callback(messenger: BinaryMessenger, method: string, args: Array<ESObject>): void {
    const channel = new BasicMessageChannel<Object>(messenger, `${PREFIX}TXLivePlayerFlutterAPI.${method}.${this.id}`, codec);
    channel.send(args);
  }
}

function playerEvent(event: number): Map<string, Object> {
  const result = new Map<string, Object>();
  result.set('event', event);
  return result;
}

function playerErrorEvent(code: number, message: string): Map<string, Object> {
  const result = playerEvent(code);
  result.set('EVT_MSG', message);
  return result;
}

function bindRenderView(player: LivePlayer, viewId: number): void {
  player.renderViewId = viewId;
  const target = renderTargets.get(viewId);
  if (target) {
    player.player.setRenderView(target.componentId);
  }
}

function bindVodRenderTarget(player: VodPlayer, viewId: number): void {
  if (player.renderViewId !== viewId) player.renderTargetReady = false;
  player.renderViewId = viewId;
  const target = renderTargets.get(viewId);
  if (target) {
    // TXVodPlayer requires the render target to be set before startVodPlay.
    // PlatformView's Dart callback can arrive before XComponent.onLoad, so
    // defer a pending URL until the surface has actually been created.
    player.player.setVideoRenderTarget(target.surfaceId);
    player.renderTargetReady = true;
    player.startPendingUrl();
  }
}

export function registerRenderTarget(viewId: number, componentId: string, surfaceId: string): void {
  renderTargets.set(viewId, { componentId, surfaceId });
  players.forEach((player: LivePlayer) => {
    if (player.renderViewId === viewId) {
      player.player.setRenderView(componentId);
    }
  });
  vodPlayers.forEach((player: VodPlayer) => {
    if (player.renderViewId === viewId) bindVodRenderTarget(player, viewId);
  });
}

export function unregisterRenderTarget(viewId: number): void {
  renderTargets.delete(viewId);
  vodPlayers.forEach((player: VodPlayer) => {
    if (player.renderViewId === viewId) player.renderTargetReady = false;
  });
}

class VodPlayer {
  id: number;
  player: TXVodPlayer;
  renderViewId?: number;
  renderTargetReady: boolean = false;
  pendingUrl?: string;
  constructor(id: number, context: common.Context, messenger: BinaryMessenger) {
    this.id = id;
    this.player = new TXVodPlayer(context);
    const callback: ITXVodPlayCallback = {
      onPlayEvent: (_player: TXVodPlayer, event: number, eventData?: Map<string, TXVodDef.ParamType>): void => {
        const payload = new Map<string, Object>();
        payload.set('event', event);
        eventData?.forEach((value: TXVodDef.ParamType, key: string) => payload.set(key, value as Object));
        this.send(messenger, 'onPlayerEvent', payload);
      },
      onNetStatus: (_player: TXVodPlayer, statusData: Map<string, TXVodDef.ParamType>): void => {
        const payload = new Map<string, Object>();
        statusData.forEach((value: TXVodDef.ParamType, key: string) => payload.set(key, value as Object));
        this.send(messenger, 'onNetEvent', payload);
      }
    };
    this.player.setVodPlayCallback(callback);
  }
  send(messenger: BinaryMessenger, method: string, payload: Map<string, Object>): void {
    const channelName = `${PREFIX}TXVodPlayerFlutterAPI.${method}.${this.id}`;
    const channel = new BasicMessageChannel<Object>(messenger, channelName, codec);
    channel.send([payload]);
  }
  start(url: string): void {
    this.pendingUrl = url;
    this.startPendingUrl();
  }
  startPendingUrl(): void {
    const url = this.pendingUrl;
    if (!url || !this.renderTargetReady) return;
    this.pendingUrl = undefined;
    this.player.startVodPlay(TXVodDef.TXPlayInfoParams.createWithUrl(url));
  }
}

class LivePlayerObserver implements V2TXLivePlayerObserver {
  private livePlayer: LivePlayer;
  private messenger: BinaryMessenger;
  constructor(livePlayer: LivePlayer, messenger: BinaryMessenger) {
    this.livePlayer = livePlayer;
    this.messenger = messenger;
  }
  onConnected(_player: V2TXLivePlayer, _extraInfo: ESObject): void {
    // Connection only confirms the transport. Do not report first-frame or
    // playback-start until LiteAV confirms that video is actually playing.
    this.livePlayer.event(this.messenger, 'onPlayerEvent', playerEvent(2001));
  }
  onVideoLoading(_player: V2TXLivePlayer, _extraInfo: ESObject): void { this.livePlayer.event(this.messenger, 'onPlayerEvent', playerEvent(2007)); }
  onVideoPlaying(_player: V2TXLivePlayer, firstPlay: boolean, _extraInfo: ESObject): void {
    this.livePlayer.event(this.messenger, 'onPlayerEvent', playerEvent(2004));
    if (firstPlay) {
      this.livePlayer.event(this.messenger, 'onPlayerEvent', playerEvent(2003));
    }
  }
  onStatisticsUpdate(_player: V2TXLivePlayer, statistics: V2TXLivePlayerStatistics): void {
    const status = new Map<string, Object>();
    status.set('VIDEO_FPS', statistics.fps);
    status.set('VIDEO_BITRATE', statistics.videoBitrate);
    this.livePlayer.event(this.messenger, 'onNetEvent', status);
  }
  onError(_player: V2TXLivePlayer, code: number, message: string, _extraInfo: ESObject): void {
    this.livePlayer.event(this.messenger, 'onPlayerEvent', playerErrorEvent(code, message));
  }
  onVideoResolutionChanged(_player: V2TXLivePlayer, width: number, height: number): void {
    const event = playerEvent(2009);
    event.set('EVT_WIDTH', width);
    event.set('EVT_HEIGHT', height);
    event.set('EVT_PARAM1', width);
    event.set('EVT_PARAM2', height);
    this.livePlayer.event(this.messenger, 'onPlayerEvent', event);
  }
  onSnapshotComplete(_player: V2TXLivePlayer, pixelMap: image.PixelMap): void {
    this.sendSnapshot(pixelMap);
  }
  private async sendSnapshot(pixelMap: image.PixelMap): Promise<void> {
    let packer: image.ImagePacker | null = null;
    try {
      packer = image.createImagePacker();
      const imageData: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      this.livePlayer.callback(this.messenger, 'onSnapshotComplete', [new Uint8Array(imageData)]);
    } catch (_error) {
      this.livePlayer.callback(this.messenger, 'onSnapshotComplete', [null]);
    } finally {
      if (packer !== null) await packer.release();
    }
  }
  onLocalRecordBegin(_player: V2TXLivePlayer, code: number, path: string): void { this.livePlayer.callback(this.messenger, 'onLocalRecordBegin', [code, path]); }
  onLocalRecording(_player: V2TXLivePlayer, duration: number, path: string): void { this.livePlayer.callback(this.messenger, 'onLocalRecording', [duration, path]); }
  onLocalRecordComplete(_player: V2TXLivePlayer, code: number, path: string): void { this.livePlayer.callback(this.messenger, 'onLocalRecordComplete', [code, path]); }
}

function replyError(reply: Reply<Object>, message: string): void { reply.reply(['ohos-error', message, null]); }
function setupChannel(messenger: BinaryMessenger, name: string, handler: (args: Array<Object>) => Object | null): void {
  const channel = new BasicMessageChannel<Object>(messenger, name, codec);
  channel.setMessageHandler({ onMessage(message: Object, reply: Reply<Object>): void { try { reply.reply([handler(message as Array<Object>)]); } catch (e) { replyError(reply, `${e}`); } } });
}
function playerById(playerId: number): LivePlayer { const player = players.get(playerId); if (!player) throw new Error('player not found'); return player; }
function playerFrom(args: Array<Object>): LivePlayer { return playerById((args[0] as PlayerMsg).playerId); }

function startLiveRecording(player: LivePlayer, values: Map<string, Object>): void {
  const filePath = values.get('filePath');
  if (typeof filePath !== 'string' || filePath.length === 0) throw new Error('recording filePath is required');
  const params = new V2TXLiveLocalRecordingParams();
  params.filePath = filePath;
  params.recordMode = V2TXLiveRecordMode.V2TXLiveRecordModeBoth;
  const interval = values.get('interval');
  if (typeof interval === 'number') params.interval = interval;
  const result = player.player.startLocalRecording(params);
  if (result !== 0) throw new Error(`startLocalRecording failed: ${result}`);
}

export function setupSuperPlayerApi(messenger: BinaryMessenger, context: common.Context): void {
  livePremier = getV2TXLivePremierShareInstance(context);
  liveLogConfig = new V2TXLiveLogConfig();
  const global = `${PREFIX}TXFlutterSuperPlayerPluginAPI.`;
  setupChannel(messenger, `${global}getLiteAVSDKVersion`, () => new StringMsg('13.2.0.8729'));
  setupChannel(messenger, `${global}createLivePlayer`, () => { const id = nextId++; players.set(id, new LivePlayer(id, context, messenger)); registerLiveChannels(messenger, id); return new PlayerMsg(id); });
  setupChannel(messenger, `${global}createVodPlayer`, () => {
    const id = nextId++;
    vodPlayers.set(id, new VodPlayer(id, context, messenger));
    registerVodChannels(messenger, id);
    return new PlayerMsg(id);
  });
  setupChannel(messenger, `${global}setGlobalLicense`, (args) => {
    const license = args[0] as LicenseMessage;
    livePremier?.setLicence(license.licenseUrl, license.licenseKey);
    return null;
  });
  setupChannel(messenger, `${global}releasePlayer`, (args) => {
    const id = (args[0] as PlayerMsg).playerId;
    const vodPlayer = vodPlayers.get(id);
    if (vodPlayer) {
      vodPlayer.player.stopPlay(true);
      vodPlayers.delete(id);
    } else {
      const player = playerById(id);
      releaseV2TXLivePlayer(player.player);
      players.delete(id);
    }
    return null;
  });
  setupChannel(messenger, `${global}setConsoleEnabled`, (args) => {
    if (liveLogConfig && livePremier) {
      liveLogConfig.enableConsole = (args[0] as BoolMsg).value;
      livePremier.setLogConfig(liveLogConfig);
    }
    return null;
  });
  setupChannel(messenger, `${global}getPlatformVersion`, () => new StringMsg('OpenHarmony'));
  setupChannel(messenger, `${global}setLogLevel`, (args) => {
    const level = (args[0] as IntMsg).value;
    if (liveLogConfig && livePremier && level >= 0 && level <= 6) {
      liveLogConfig.logLevel = level as V2TXLiveLogLevel;
      livePremier.setLogConfig(liveLogConfig);
    }
    return null;
  });
  setupChannel(messenger, `${global}setGlobalMaxCacheSize`, () => null);
  setupChannel(messenger, `${global}setUserId`, () => null);
  setupChannel(messenger, `${global}setLicenseFlexibleValid`, () => null);

  const live = `${PREFIX}TXFlutterLivePlayerApi.`;
  setupChannel(messenger, `${live}startLivePlay`, (args) => { const p = playerFrom(args); const a = args[0] as StringMsg; return new BoolMsg(p.startPlay(a.value) === 0); });
  setupChannel(messenger, `${live}stop`, (args) => new BoolMsg(playerFrom(args).stopPlay() === 0));
  setupChannel(messenger, `${live}isPlaying`, (args) => new BoolMsg(playerFrom(args).player.isPlaying() === 1));
  setupChannel(messenger, `${live}pause`, (args) => { playerFrom(args).pause(); return null; });
  setupChannel(messenger, `${live}resume`, (args) => { playerFrom(args).resume(); return null; });
  setupChannel(messenger, `${live}setMute`, (args) => { const mute = args[0] as BoolMsg; if (mute.playerId === undefined) throw new Error('player id required'); playerById(mute.playerId).setMute(mute.value); return null; });
  setupChannel(messenger, `${live}setPlayerView`, (args) => { bindRenderView(playerFrom(args), args[0] as number); return null; });
  setupChannel(messenger, `${live}setRenderMode`, (args) => { const p = playerFrom(args); p.player.setRenderFillMode(V2TXLiveFillMode.V2TXLiveFillModeFill); return null; });
  setupChannel(messenger, `${live}enableHardwareDecode`, (args) => {
    const p = playerFrom(args);
    const enable = (args[0] as BoolMsg).value;
    return new BoolMsg(p.player.setProperty(V2TXLiveProperty.kV2EnableHardwareAcceleration, enable) === 0);
  });
  setupChannel(messenger, `${live}snapshot`, () => null);
  setupChannel(messenger, `${live}startLocalRecording`, (args) => { const p = playerFrom(args); const map = args[0] as Map<string, Object>; const params = new V2TXLiveLocalRecordingParams(); params.filePath = map.get('filePath') as string; params.interval = map.get('interval') as number; return p.player.startLocalRecording(params); });
  setupChannel(messenger, `${live}stopLocalRecording`, (args) => { playerFrom(args).player.stopLocalRecording(); return null; });
}

function registerLiveChannels(messenger: BinaryMessenger, id: number): void {
  const pfx = `${PREFIX}TXFlutterLivePlayerApi.`;
  const suffix = `.${id}`;
  const get = () => { const p = players.get(id); if (!p) throw new Error('player not found'); return p; };
  setupChannel(messenger, `${pfx}startLivePlay${suffix}`, (args) => new BoolMsg(get().startPlay((args[0] as StringMsg).value) === 0));
  setupChannel(messenger, `${pfx}stop${suffix}`, () => new BoolMsg(get().stopPlay() === 0));
  setupChannel(messenger, `${pfx}isPlaying${suffix}`, () => new BoolMsg(get().player.isPlaying() === 1));
  setupChannel(messenger, `${pfx}pause${suffix}`, () => { get().pause(); return null; });
  setupChannel(messenger, `${pfx}resume${suffix}`, () => { get().resume(); return null; });
  setupChannel(messenger, `${pfx}setMute${suffix}`, (args) => { get().setMute((args[0] as BoolMsg).value); return null; });
  setupChannel(messenger, `${pfx}setPlayerView${suffix}`, (args) => { bindRenderView(get(), args[0] as number); return null; });
  setupChannel(messenger, `${pfx}setRenderMode${suffix}`, () => { get().player.setRenderFillMode(V2TXLiveFillMode.V2TXLiveFillModeFill); return null; });
  setupChannel(messenger, `${pfx}enableHardwareDecode${suffix}`, (args) => {
    const enable = (args[0] as BoolMsg).value;
    return new BoolMsg(get().player.setProperty(V2TXLiveProperty.kV2EnableHardwareAcceleration, enable) === 0);
  });
  setupChannel(messenger, `${pfx}snapshot${suffix}`, () => {
    const livePlayer = get();
    if (livePlayer.player.snapshot() !== 0) {
      livePlayer.callback(messenger, 'onSnapshotComplete', [null]);
    }
    return null;
  });
  setupChannel(messenger, `${pfx}startLocalRecording${suffix}`, (args) => { startLiveRecording(get(), args[0] as Map<string, Object>); return null; });
  setupChannel(messenger, `${pfx}stopLocalRecording${suffix}`, () => { get().player.stopLocalRecording(); return null; });
}

function registerVodChannels(messenger: BinaryMessenger, id: number): void {
  const prefix = `${PREFIX}TXFlutterVodPlayerApi.`;
  const suffix = `.${id}`;
  const get = (): VodPlayer => {
    const player = vodPlayers.get(id);
    if (!player) throw new Error('VOD player not found');
    return player;
  };

  setupChannel(messenger, `${prefix}startVodPlay${suffix}`, (args) => {
    const vodPlayer = get();
    const url = (args[0] as StringMsg).value;
    vodPlayer.start(url);
    return new BoolMsg(true);
  });
  setupChannel(messenger, `${prefix}setConfig${suffix}`, (args) => {
    const configMessage: Array<ESObject> = (args[0] as VodPlayConfigMsg).values;
    const config = new TXVodPlayConfig();
    if (configMessage[1] !== null) config.connectRetryCount = configMessage[1] as number;
    if (configMessage[2] !== null) config.connectRetryInterval = configMessage[2] as number;
    if (configMessage[3] !== null) config.timeout = configMessage[3] as number;
    if (configMessage[5] !== null) config.headers = configMessage[5] as Map<string, string>;
    if (configMessage[6] !== null) config.enableAccurateSeek = configMessage[6] as boolean;
    if (configMessage[8] !== null) config.smoothSwitchBitrate = configMessage[8] as boolean;
    if (configMessage[10] !== null) config.progressInterval = configMessage[10] as number;
    if (configMessage[11] !== null) config.maxBufferSize = configMessage[11] as number;
    if (configMessage[12] !== null) config.maxPreloadSize = configMessage[12] as number;
    if (configMessage[19] !== null) config.preferredResolution = configMessage[19] as number;
    if (configMessage[20] !== null) config.mediaType = configMessage[20] as number;
    get().player.setConfig(config);
    return null;
  });
  setupChannel(messenger, `${prefix}stop${suffix}`, (args) => {
    const vodPlayer = get();
    vodPlayer.pendingUrl = undefined;
    const clearLastFrame = (args[0] as BoolMsg).value;
    const result = vodPlayer.player.stopPlay(clearLastFrame);
    return new BoolMsg(result === 0);
  });
  setupChannel(messenger, `${prefix}isPlaying${suffix}`, () => new BoolMsg(get().player.isPlaying()));
  setupChannel(messenger, `${prefix}pause${suffix}`, () => { get().player.pause(); return null; });
  setupChannel(messenger, `${prefix}resume${suffix}`, () => { get().player.resume(); return null; });
  setupChannel(messenger, `${prefix}setMute${suffix}`, (args) => { get().player.setMute((args[0] as BoolMsg).value); return null; });
  setupChannel(messenger, `${prefix}seek${suffix}`, (args) => { get().player.seek((args[0] as DoubleMsg).value); return null; });
  setupChannel(messenger, `${prefix}setRate${suffix}`, (args) => { get().player.setRate((args[0] as DoubleMsg).value); return null; });
  setupChannel(messenger, `${prefix}setPlayerView${suffix}`, (args) => {
    const viewId = args[0] as number;
    bindVodRenderTarget(get(), viewId);
    return null;
  });
  setupChannel(messenger, `${prefix}setRenderMode${suffix}`, (_args) => null);
  setupChannel(messenger, `${prefix}enableHardwareDecode${suffix}`, (_args) => new BoolMsg(false));
  setupChannel(messenger, `${prefix}getDuration${suffix}`, () => new DoubleMsg(get().player.getDuration()));
  setupChannel(messenger, `${prefix}getCurrentPlaybackTime${suffix}`, () => new DoubleMsg(get().player.getCurrentPlaybackTime()));
  setupChannel(messenger, `${prefix}getBufferDuration${suffix}`, () => new DoubleMsg(get().player.getBufferDuration()));
  setupChannel(messenger, `${prefix}getPlayableDuration${suffix}`, () => new DoubleMsg(get().player.getPlayableDuration()));
  setupChannel(messenger, `${prefix}getWidth${suffix}`, () => new IntMsg(get().player.getWidth()));
  setupChannel(messenger, `${prefix}getHeight${suffix}`, () => new IntMsg(get().player.getHeight()));
  setupChannel(messenger, `${prefix}setAutoPlay${suffix}`, (args) => { get().player.setAutoPlay((args[0] as BoolMsg).value); return null; });
}
