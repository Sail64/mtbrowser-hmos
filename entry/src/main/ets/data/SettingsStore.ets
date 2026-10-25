import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { PrefsDb } from './PrefsDb';

/** 轻量元数据（不属于任何 Site 的全局状态）。对应 Android storage/Prefs.kt。 */
export class SettingsStore {
  private static readonly KEY_LAST_URL = 'last_url';
  /** 与 Android Prefs 同名同语义（fab_x / fab_y） */
  private static readonly KEY_FAB_X = 'fab_x';
  private static readonly KEY_FAB_Y = 'fab_y';

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
}