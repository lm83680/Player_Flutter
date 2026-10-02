import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { V2TXLivePlayer, V2TXLivePlayerObserver, V2TXLivePremier, V2TXLiveLogConfig, V2TXLiveLogLevel, createV2TXLivePlayer, releaseV2TXLivePlayer, getV2TXLivePremierShareInstance, V2TXLiveFillMode, V2TXLiveLocalRecordingParams, V2TXLiveProperty } from 'liteavsdk';
import common from '@ohos.app.ability.common';
import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';

const PREFIX = 'dev.flutter.pigeon.super_player.';
const VIEW_TYPE = 'FTXRenderViewType';
class Codec extends StandardMessageCodec {
  writeValue(stream: ByteBuffer, value: ESObject): ESObject {
    if (value instanceof PlayerMsg) { stream.writeUint8(129); return this.writeValue(stream, [value.playerId]); }
    if (value instanceof BoolMsg) { stream.writeUint8(145); return this.writeValue(stream, [value.value]); }
    if (value instanceof IntMsg) { stream.writeUint8(146); return this.writeValue(stream, [value.value]); }
    if (value instanceof StringMsg) { stream.writeUint8(147); return this.writeValue(stream, [value.value]); }
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
      case 145:
        return new BoolMsg((this.readValue(buffer) as Array<Object>)[0] as boolean);
      case 146:
        return new IntMsg((this.readValue(buffer) as Array<Object>)[0] as number);
      case 147:
        return new StringMsg((this.readValue(buffer) as Array<Object>)[0] as string);
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
const codec = new Codec();
const players = new Map<number, LivePlayer>();
const renderViewIds = new Map<number, string>();
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
  callback(messenger: BinaryMessenger, method: string, args: Array<Object>): void {
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
  const componentId = renderViewIds.get(viewId);
  if (componentId) {
    player.player.setRenderView(componentId);
  }
}

export function registerRenderView(viewId: number, componentId: string): void {
  renderViewIds.set(viewId, componentId);
  players.forEach((player: LivePlayer) => {
    if (player.renderViewId === viewId) {
      player.player.setRenderView(componentId);
    }
  });
}

export function unregisterRenderView(viewId: number): void {
  renderViewIds.delete(viewId);
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
  onVideoPlaying(_player: V2TXLivePlayer, _firstPlay: boolean, _extraInfo: ESObject): void {
    this.livePlayer.event(this.messenger, 'onPlayerEvent', playerEvent(2004));
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

export function setupSuperPlayerApi(messenger: BinaryMessenger, context: common.Context): void {
  livePremier = getV2TXLivePremierShareInstance(context);
  liveLogConfig = new V2TXLiveLogConfig();
  const global = `${PREFIX}TXFlutterSuperPlayerPluginAPI.`;
  setupChannel(messenger, `${global}getLiteAVSDKVersion`, () => new StringMsg('13.2.0.8729'));
  setupChannel(messenger, `${global}createLivePlayer`, () => { const id = nextId++; players.set(id, new LivePlayer(id, context, messenger)); registerLiveChannels(messenger, id); return new PlayerMsg(id); });
  setupChannel(messenger, `${global}createVodPlayer`, () => { throw new Error('VOD bridge is not implemented in the Flutter OHOS adapter'); });
  setupChannel(messenger, `${global}setGlobalLicense`, (args) => {
    const license = args[0] as LicenseMessage;
    livePremier?.setLicence(license.licenseUrl, license.licenseKey);
    return null;
  });
  setupChannel(messenger, `${global}releasePlayer`, (args) => { const p = playerFrom(args); releaseV2TXLivePlayer(p.player); players.delete(p.id); return null; });
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
  setupChannel(messenger, `${pfx}snapshot${suffix}`, () => null);
  setupChannel(messenger, `${pfx}startLocalRecording${suffix}`, (args) => { const map = args[0] as Map<string, Object>; const params = new V2TXLiveLocalRecordingParams(); params.filePath = map.get('filePath') as string; params.interval = map.get('interval') as number; return get().player.startLocalRecording(params); });
  setupChannel(messenger, `${pfx}stopLocalRecording${suffix}`, () => { get().player.stopLocalRecording(); return null; });
}
