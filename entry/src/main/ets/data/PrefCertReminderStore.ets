import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { CertKind, kindLabel } from '../domain/model/CertModels';
import { CertReminderScheduler } from '../domain/CertReminderScheduler';
import { PrefsDb } from './PrefsDb';

interface WarnRow {
  k: string;
  at: number;
}

const KEY = 'cert_warn_at';
const INTERVAL_MS = 24 * 60 * 60 * 1000;

function kOf(host: string, kind: CertKind): string {
  return `${kindLabel(kind)}:${host}`;
}

/**
 * 证书提醒时间戳存储：同一 host + 类别每 24h 最多提醒一次（持久化）。
 * 对应 Android PrefCertReminderStore。
 */
export class PrefCertReminderStore implements CertReminderScheduler {
  private db: preferences.Preferences;

  constructor(context: common.Context) {
    this.db = PrefsDb.of(context);
  }

  private load(): Map<string, number> {
    const map = new Map<string, number>();
    const raw = PrefsDb.getString(this.db, KEY);
    if (raw === '') {
      return map;
    }
    try {
      const rows = JSON.parse(raw) as WarnRow[];
      for (const r of rows) {
        map.set(r.k, r.at);
      }
    } catch (e) {
      // 损坏视为空
    }
    return map;
  }

  private save(map: Map<string, number>): void {
    const rows: WarnRow[] = [];
    map.forEach((at: number, k: string): void => {
      rows.push({ k: k, at: at });
    });
    PrefsDb.putString(this.db, KEY, JSON.stringify(rows));
  }

  shouldRemind(host: string, kind: CertKind, now?: number): boolean {
    const t = now ?? Date.now();
    const last = this.load().get(kOf(host, kind));
    if (last === undefined) {
      return true;
    }
    return t - last >= INTERVAL_MS;
  }

  markReminded(host: string, kind: CertKind, now?: number): void {
    const map = this.load();
    map.set(kOf(host, kind), now ?? Date.now());
    this.save(map);
  }
}
