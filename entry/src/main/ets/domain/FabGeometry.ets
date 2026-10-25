/**
 * 悬浮按钮几何规则（对应 Android MainActivity 里的 clampFab / restoreFabPosition）。
 * 纯计算，零平台依赖：把"按钮能不能被拖出屏幕""默认摆哪儿"这类规则从 UI 里拿出来，
 * 这样它能被冒烟测试钉住。
 */

export class FabPoint {
  x: number;
  y: number;
  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }
}

/** 未持久化过的哨兵值（与 Android restoreFabPosition 的 null 语义等价）。 */
export const FAB_UNSET: number = -1;

export class FabGeometry {
  /** 持久化值是否有效（写过且非负）。 */
  static isSet(x: number, y: number): boolean {
    return x >= 0 && y >= 0;
  }

  /**
   * 把坐标夹进容器内。
   * 容器尺寸未知（<=0，布局尚未完成）时返回 (0,0)，调用方应等 onAreaChange 后再定位。
   */
  static clamp(x: number, y: number, containerW: number, containerH: number, fabSize: number): FabPoint {
    if (containerW <= 0 || containerH <= 0) {
      return new FabPoint(0, 0);
    }
    const maxX = Math.max(0, containerW - fabSize);
    const maxY = Math.max(0, containerH - fabSize);
    return new FabPoint(
      Math.min(Math.max(0, x), maxX),
      Math.min(Math.max(0, y), maxY)
    );
  }

  /** 默认位置：右上角（与 Android 初始摆放一致）。 */
  static defaultTopRight(containerW: number, containerH: number, fabSize: number, margin: number): FabPoint {
    if (containerW <= 0 || containerH <= 0) {
      return new FabPoint(FAB_UNSET, FAB_UNSET);
    }
    return FabGeometry.clamp(containerW - fabSize - margin, margin, containerW, containerH, fabSize);
  }
}