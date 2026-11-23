import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_player/super_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const prefix = 'dev.flutter.pigeon.super_player.';
  final create = BasicMessageChannel<Object?>(
    '${prefix}TXFlutterSuperPlayerPluginAPI.createLivePlayer',
    TXFlutterSuperPlayerPluginAPI.pigeonChannelCodec,
  );
  final release = BasicMessageChannel<Object?>(
    '${prefix}TXFlutterSuperPlayerPluginAPI.releasePlayer',
    TXFlutterSuperPlayerPluginAPI.pigeonChannelCodec,
  );
  final start = BasicMessageChannel<Object?>(
    '${prefix}TXFlutterLivePlayerApi.startLocalRecording.42',
    TXFlutterLivePlayerApi.pigeonChannelCodec,
  );
  final stop = BasicMessageChannel<Object?>(
    '${prefix}TXFlutterLivePlayerApi.stopLocalRecording.42',
    TXFlutterLivePlayerApi.pigeonChannelCodec,
  );
  late TXLivePlayerController controller;
  Map<Object?, Object?>? nativeParams;
  var stops = 0;

  setUp(() {
    nativeParams = null;
    stops = 0;
    messenger.setMockDecodedMessageHandler<Object?>(
        create, (_) async => [PlayerMsg(playerId: 42)]);
    messenger.setMockDecodedMessageHandler<Object?>(
        release, (_) async => [null]);
    messenger.setMockDecodedMessageHandler<Object?>(start, (message) async {
      nativeParams = (message as List<Object?>).single as Map<Object?, Object?>;
      return [null];
    });
    messenger.setMockDecodedMessageHandler<Object?>(stop, (_) async {
      stops++;
      return [null];
    });
    controller = TXLivePlayerController();
  });

  tearDown(() async {
    await controller.dispose();
    TXLivePlayerFlutterAPI.setUp(null, messageChannelSuffix: '42');
    for (final channel in [create, release, start, stop]) {
      messenger.setMockDecodedMessageHandler<Object?>(channel, null);
    }
  });

  test('existing callers keep audio and video recording', () async {
    await controller.startLocalRecording(
        FTXLiveLocalRecordingParams(filePath: '/tmp/both.mp4'));
    expect(nativeParams,
        {'filePath': '/tmp/both.mp4', 'interval': -1, 'recordMode': 0});
    expect(
        FTXLiveLocalRecordingParams.fromJson({'filePath': '/tmp/legacy.mp4'})
            .recordMode,
        FTXLiveRecordMode.both);
  });

  test('video only mode reaches native recorder through Pigeon', () async {
    final params = FTXLiveLocalRecordingParams(
      filePath: '/tmp/silent.mp4',
      interval: 1000,
      recordMode: FTXLiveRecordMode.videoOnly,
    );
    await controller.startLocalRecording(params);
    expect(nativeParams,
        {'filePath': '/tmp/silent.mp4', 'interval': 1000, 'recordMode': 1});
    expect(FTXLiveLocalRecordingParams.fromJson(params.toJson()).recordMode,
        FTXLiveRecordMode.videoOnly);
    await controller.stopLocalRecording();
    expect(stops, 1);
  });
}
