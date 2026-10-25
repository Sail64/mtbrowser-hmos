import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ClientCertIdentityStore } from '../domain/ClientCertSelector';
import { PrefsDb } from './PrefsDb';

interface AliasRow {
  host: string;
  uri: string;
}

const KEY = 'client_cert_aliases';

/**
 * 按 host 隔离的客户端凭据 identity（鸿蒙为 keyUri）缓存存储。
 * 对应 Android PrefClientCertStore；chooseIdentity 交互在 platform 层实现。
 */
export class PrefClientCertStore implements ClientCertIdentityStore {
  private db: preferences.Preferences;

  constructor(context: common.Context) {
    this.db = PrefsDb.of(context);
  }

  private load(): Map<string, string> {
    const map = new Map<string, string>();
    const raw = PrefsDb.getString(this.db, KEY);
    if (raw === '') {
      return map;
    }
    try {
      const rows = JSON.parse(raw) as AliasRow[];
      for (const r of rows) {
        map.set(r.host, r.uri);
      }
    } catch (e) {
      // 存储损坏视为空（与 Android 版一致）
    }
    return map;
  }

  private save(map: Map<string, string>): void {
    const rows: AliasRow[] = [];
    map.forEach((uri: string, host: string): void => {
      rows.push({ host: host, uri: uri });
    });
    PrefsDb.putString(this.db, KEY, JSON.stringify(rows));
  }

  cachedIdentity(host: string): string | null {
    const v = this.load().get(host);
    return v === undefined ? null : v;
  }

  saveIdentity(host: string, identity: string): void {
    const map = this.load();
    map.set(host, identity);
    this.save(map);
  }

  clearIdentity(host: string): void {
    const map = this.load();
    map.delete(host);
    this.save(map);
  }
}
