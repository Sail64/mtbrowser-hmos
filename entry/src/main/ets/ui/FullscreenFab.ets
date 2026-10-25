import { AppGraph } from '../app/AppGraph';
import { FabGeometry, FabPoint, FAB_UNSET } from '../domain/FabGeometry';

/** 悬浮全屏按钮尺寸与边距（vp）。 */
const FAB_SIZE: number = 36;
const FAB_MARGIN: number = 10;

/**
 * 悬浮全屏按钮（对应 Android MainActivity 的 btnFullscreen + setupFabDrag）：
 * 点击切换全屏，可拖动，位置持久化，容器尺寸变化（顶部栏显隐）后自动钳入边界。
 * 几何规则在 domain/FabGeometry（纯逻辑、可冒烟），这里只负责手势与渲染。
 */
@Component
export struct FullscreenFab {
  @Prop fullscreen: boolean = false;
  /** 所在容器尺寸：由父层 onAreaChange 传入，未布局时为 0 */
  @Prop containerW: number = 0;
  @Prop containerH: number = 0;
  onToggle: () => void = (): void => {};

  @State x: number = FAB_UNSET;
  @State y: number = FAB_UNSET;
  @State dragging: boolean = false;
  private startX: number = 0;
  private startY: number = 0;

  aboutToAppear(): void {
    this.x = AppGraph.settings().getFabX();
    this.y = AppGraph.settings().getFabY();
  }

  private currentPoint(): FabPoint {
    if (!FabGeometry.isSet(this.x, this.y)) {
      return FabGeometry.defaultTopRight(this.containerW, this.containerH, FAB_SIZE, FAB_MARGIN);
    }
    return FabGeometry.clamp(this.x, this.y, this.containerW, this.containerH, FAB_SIZE);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 图标空白与三元表达式无关：顶栏 `starred ? $r(ic_star_on) : $r(ic_star)` 一直正常。
      // 真因是 Image 同时设 .width(16).height(16).padding(10) —— 内容区被 padding 吃成负数。
      // 现在由外层 Stack 负责尺寸与底色，Image 只画 16×16 图。
      if (this.fullscreen) {
        Image($r('app.media.ic_collapse'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        Image($r('app.media.ic_expand'))
          .width(16)
          .height(16)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .backgroundColor(this.dragging ? '#E6F2F3F5' : '#D9FFFFFF')
    .borderRadius(FAB_SIZE / 2)
    .borderWidth(0.5)
    .borderColor('#1A000000')
    .shadow({ radius: 8, color: '#1F000000', offsetY: 2 })
    .position({ x: this.currentPoint().x, y: this.currentPoint().y })
    // 容器尺寸未知（onAreaChange 还没回来）时钳制结果是 (-1,-1)，会闪一下左上角：
    // 位置未定时先不画，等拿到容器尺寸再出现。
    .visibility(this.containerW > 0 && this.containerH > 0 ? Visibility.Visible : Visibility.Hidden)
    .zIndex(10)
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ fingers: 1, distance: 6 })
          .onActionStart(() => {
            const p = this.currentPoint();
            this.startX = p.x;
            this.startY = p.y;
            this.dragging = true;
          })
          .onActionUpdate((event: GestureEvent) => {
            const p = FabGeometry.clamp(this.startX + event.offsetX, this.startY + event.offsetY,
              this.containerW, this.containerH, FAB_SIZE);
            this.x = p.x;
            this.y = p.y;
          })
          .onActionEnd(() => {
            this.dragging = false;
            AppGraph.settings().setFabPos(this.x, this.y);
          })
          .onActionCancel(() => {
            this.dragging = false;
          }),
        TapGesture({ count: 1 })
          .onAction(() => {
            this.onToggle();
          })
      )
    )
  }
}