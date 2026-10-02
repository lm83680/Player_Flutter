import { BinaryMessenger, FlutterPlugin, FlutterPluginBinding, PlatformView, PlatformViewFactory, StandardMessageCodec, MethodChannel, StandardMethodCodec } from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { registerRenderView as registerNativeRenderView, setupSuperPlayerApi, unregisterRenderView as unregisterNativeRenderView } from './SuperPlayerMessages';

const VIEW_TYPE = 'FTXRenderViewType';

class RenderView extends PlatformView {
  private channel: MethodChannel;
  private viewId: number;
  constructor(messenger: BinaryMessenger, viewId: number) {
    super();
    this.viewId = viewId;
    this.channel = new MethodChannel(messenger, `${VIEW_TYPE}${viewId}`, StandardMethodCodec.INSTANCE);
  }
  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(RenderBuilder);
  }
  getComponentId(): string { return `${VIEW_TYPE}_${this.viewId}`; }
  registerRenderView(): void { registerNativeRenderView(this.viewId, this.getComponentId()); }
  dispose(): void {
    unregisterNativeRenderView(this.viewId);
    this.channel.setMethodCallHandler(null);
  }
}

@Builder
function RenderBuilder(params: Params) {
  RenderSurface({ params: params });
}

@Component
struct RenderSurface {
  @Prop params: Params;
  private renderView: RenderView = this.params.platformView as RenderView;

  build() {
    Column() {
      XComponent({
        id: this.renderView.getComponentId(),
        type: XComponentType.SURFACE,
        libraryname: 'liteavsdk'
      })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.renderView.registerRenderView();
        })
    }
    .width('100%')
    .height('100%');
  }
}

class RenderViewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;
  constructor(messenger: BinaryMessenger) { super(StandardMessageCodec.INSTANCE); this.messenger = messenger; }
  create(context: common.Context, viewId: number, args: object): PlatformView {
    return new RenderView(this.messenger, viewId);
  }
}

export default class SuperPlayerPlugin implements FlutterPlugin {
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    binding.getPlatformViewRegistry().registerViewFactory(VIEW_TYPE, new RenderViewFactory(binding.getBinaryMessenger()));
    setupSuperPlayerApi(binding.getBinaryMessenger(), binding.getApplicationContext());
  }
  onDetachedFromEngine(binding: FlutterPluginBinding): void {}
  getUniqueClassName(): string { return 'SuperPlayerPlugin'; }
}
