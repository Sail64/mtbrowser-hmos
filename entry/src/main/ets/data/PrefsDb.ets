import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/**
 * preferences 单例入口：全应用共用文件 'mtls_webview'
 * （与 Android SharedPreferences 文件同名，语义对齐）。
 */
export class PrefsDb {
  static readonly FILE = 'mtls_webview';

  private static instance: preferences.Preferences | undefined = undefined;

  static of(context: common.Context): preferences.Preferences {
    if (PrefsDb.instance === undefined) {
      PrefsDb.instance = preferences.getPreferencesSync(context, { name: PrefsDb.FILE });
    }
    return PrefsDb.instance;
  }

  static getString(db: preferences.Preferences, key: string): string {
    return db.getSync(key, '') as string;
  }

  static putString(db: preferences.Preferences, key: string, value: string): void {
    db.putSync(key, value);
    db.flushSync();
  }
}
