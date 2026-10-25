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

  private db: preferences.Preferences;

  constructor(context: common.Context) {
    this.db = PrefsDb.of(context);
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

  setOpenTabs(urls: string[], currentIndex: number): void {
    try {
      PrefsDb.putString(this.db, SettingsStore.KEY_OPEN_TABS, JSON.stringify(urls));
      PrefsDb.putString(this.db, SettingsStore.KEY_OPEN_TABS_CURRENT, Math.max(0, Math.trunc(currentIndex)).toString());
    } catch (e) {
      // 存不进去不影响使用，下次启动退回单页恢复
    }
  }
}