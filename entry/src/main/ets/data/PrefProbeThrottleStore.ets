import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ProbeThrottle } from '../domain/ProbeThrottle';
import { PrefsDb } from './PrefsDb';

interface ProbeRow {
  host: string;
  at: number;
}

const KEY = 'cert_probe_at';
const INTERVAL_MS = 24 * 60 * 60 * 1000;

/**
 * 旁路探测限频：与「提醒」分离——探测无论结果如何都要记录时间。
 * 对应 Android PrefProbeThrottleStore（MVP 未接探测器，端口先住 domain，见架构文档扩展位）。
 */
export class PrefProbeThrottleStore implements ProbeThrottle {
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
      const rows = JSON.parse(raw) as ProbeRow[];
      for (const r of rows) {
        map.set(r.host, r.at);
      }
    } catch (e) {
      // 损坏视为空
    }
    return map;
  }

  private save(map: Map<string, number>): void {
    const rows: ProbeRow[] = [];
    map.forEach((at: number, host: string): void => {
      rows.push({ host: host, at: at });
    });
    PrefsDb.putString(this.db, KEY, JSON.stringify(rows));
  }

  shouldRun(host: string, now?: number): boolean {
    const t = now ?? Date.now();
    const last = this.load().get(host);
    if (last === undefined) {
      return true;
    }
    return t - last >= INTERVAL_MS;
  }

  markRun(host: string, now?: number): void {
    const map = this.load();
    map.set(host, now ?? Date.now());
    this.save(map);
  }
}
