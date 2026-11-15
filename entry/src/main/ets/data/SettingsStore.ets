import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PrefsDb } from './PrefsDb';

/** 轻量元数据（不属于任何 Site 的全局状态）。对应 Android storage/Prefs.kt。 */
export class SettingsStore {
  private static readonly KEY_LAST_URL = 'last_url';
  /** 与 Android Prefs 同名同语义（fab_x / fab_y） */
  private static readonly KEY_FAB_X = 'fab_x';
  private static readonly KEY_FAB_Y = 'fab_y';
  /** 上次退出时打开的标签（JSON 字符串数组）+ 当前标签下标 */
  private static readonly KEY_OPEN_TABS = 'open_tabs';
  private static readonly KEY_OPEN_TABS_CURRENT = 'open_tabs_current';
  /** 指纹锁：开关 / 后台停留多久后要求解锁（分钟）/ 最近一次进入后台的时间戳 */
  private static readonly KEY_LOCK_ENABLED = 'lock_enabled';
  private static readonly KEY_LOCK_TIMEOUT_MIN = 'lock_timeout_min';
  private static readonly KEY_LOCK_LAST_BG = 'lock_last_bg_at';
  /** 窗口隐私模式：任务列表里不显示页面内容（同时禁止截屏）。默认开，只有显式存 '0' 才关。 */
  private static readonly KEY_HIDE_RECENTS = 'hide_recents';

  private db: preferences.Preferences;

  constructor(context: common.Context) {
    this.db = PrefsDb.of(context);
  }

  /**
   * 任务列表预览是否隐藏（窗口隐私模式）。默认 true：
   * 浏览器页面里可能是私密内容，默认不泄露，需要截图的人自己去设置里关。
   */
  getHideRecents(): boolean {
    return PrefsDb.getString(this.db, SettingsStore.KEY_HIDE_RECENTS) !== '0';
  }

  setHideRecents(enabled: boolean): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_HIDE_RECENTS, enabled ? '1' : '0');
  }

  getLastUrl(): string {
    return PrefsDb.getString(this.db, SettingsStore.KEY_LAST_URL);
  }

  setLastUrl(url: string): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_LAST_URL, url);
  }

  /** 悬浮按钮位置；未记录过返回 -1（调用方用 FabGeometry.isSet 判断）。 */
  getFabX(): number {
    return SettingsStore.parseCoord(PrefsDb.getString(this.db, SettingsStore.KEY_FAB_X));
  }

  getFabY(): number {
    return SettingsStore.parseCoord(PrefsDb.getString(this.db, SettingsStore.KEY_FAB_Y));
  }

  setFabPos(x: number, y: number): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_FAB_X, Math.round(x).toString());
    PrefsDb.putString(this.db, SettingsStore.KEY_FAB_Y, Math.round(y).toString());
  }

  private static parseCoord(raw: string): number {
    if (raw === '') {
      return -1;
    }
    const n = Number(raw);
    return Number.isFinite(n) ? n : -1;
  }

  /**
   * 上次退出时的标签 URL 列表（空标签存空串）。
   * 解析失败一律当"没有记录"处理：宁可恢复到单个首页，也不要因为脏数据起不来。
   */
  getOpenTabs(): string[] {
    const raw = PrefsDb.getString(this.db, SettingsStore.KEY_OPEN_TABS);
    if (raw === '') {
      return [];
    }
    try {
      const arr = JSON.parse(raw) as string[];
      if (!Array.isArray(arr)) {
        return [];
      }
      const out: string[] = [];
      for (const it of arr) {
        out.push(typeof it === 'string' ? it : '');
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  getOpenTabsCurrent(): number {
    const raw = PrefsDb.getString(this.db, SettingsStore.KEY_OPEN_TABS_CURRENT);
    if (raw === '') {
      return 0;
    }
    const n = Number(raw);
    return Number.isFinite(n) && n >= 0 ? Math.trunc(n) : 0;
  }

  // ---------- 指纹锁 ----------

  getLockEnabled(): boolean {
    return PrefsDb.getString(this.db, SettingsStore.KEY_LOCK_ENABLED) === '1';
  }

  setLockEnabled(enabled: boolean): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_LOCK_ENABLED, enabled ? '1' : '0');
  }

  /** 未设置或脏数据 → 交给 domain/LockPolicy.normalizeLockTimeout 收敛 */
  getLockTimeoutMinutes(): number {
    const raw = PrefsDb.getString(this.db, SettingsStore.KEY_LOCK_TIMEOUT_MIN);
    if (raw === '') {
      return -1; // 用 -1 表示"没存过"，由调用方给默认值
    }
    const n = Number(raw);
    return Number.isFinite(n) ? Math.trunc(n) : -1;
  }

  setLockTimeoutMinutes(minutes: number): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_LOCK_TIMEOUT_MIN, Math.trunc(minutes).toString());
  }

  /** 0 = 从未进过后台 */
  getLockLastBackgroundAt(): number {
    const raw = PrefsDb.getString(this.db, SettingsStore.KEY_LOCK_LAST_BG);
    if (raw === '') {
      return 0;
    }
    const n = Number(raw);
    return Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
  }

  setLockLastBackgroundAt(at: number): void {
    PrefsDb.putString(this.db, SettingsStore.KEY_LOCK_LAST_BG, Math.max(0, Math.trunc(at)).toString());
  }

  setOpenTabs(urls: string[], currentIndex: number): void {
    try {
      PrefsDb.putString(this.db, SettingsStore.KEY_OPEN_TABS, JSON.stringify(urls));
      PrefsDb.putString(this.db, SettingsStore.KEY_OPEN_TABS_CURRENT, Math.max(0, Math.trunc(currentIndex)).toString());
    } catch (e) {
      // 存不进去不影响使用，下次启动退回单页恢复
    }
  }
}