import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Site } from '../domain/model/Site';
import { SiteRepository } from '../domain/SiteRepository';
import { UrlLite } from '../domain/UrlLite';
import { PrefsDb } from './PrefsDb';

interface SiteRow {
  id: string;
  name: string;
  url: string;
  createdAt: number;
}

const KEY = 'sites';

function normalize(url: string): string {
  return url.trim().replace(/\/+$/, '');
}

/** 时间戳+随机数生成站点 id（仅需唯一性，不需要标准 UUID）。 */
function newId(): string {
  return `${Date.now().toString(36)}-${Math.floor(Math.random() * 0xFFFFFF).toString(36)}`;
}

/** 站点（书签）仓库：preferences + JSON 实现（对应 Android PrefSiteRepository）。 */
export class PrefSiteRepository implements SiteRepository {
  private db: preferences.Preferences;

  constructor(context: common.Context) {
    this.db = PrefsDb.of(context);
  }

  private load(): Site[] {
    const raw = PrefsDb.getString(this.db, KEY);
    if (raw === '') {
      return [];
    }
    try {
      const rows = JSON.parse(raw) as SiteRow[];
      const out: Site[] = [];
      for (const r of rows) {
        out.push(new Site(r.id, r.name, r.url, r.createdAt ?? 0));
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  private save(sites: Site[]): void {
    const rows: SiteRow[] = [];
    for (const s of sites) {
      rows.push({ id: s.id, name: s.name, url: s.url, createdAt: s.createdAt });
    }
    PrefsDb.putString(this.db, KEY, JSON.stringify(rows));
  }

  all(): Site[] {
    return this.load();
  }

  byHost(host: string): Site | null {
    for (const s of this.load()) {
      if (UrlLite.hostOf(s.url) === host) {
        return s;
      }
    }
    return null;
  }

  findByUrl(url: string): Site | null {
    const target = normalize(url);
    for (const s of this.load()) {
      if (normalize(s.url) === target) {
        return s;
      }
    }
    return null;
  }

  add(name: string, url: string): Site {
    const sites = this.load();
    const fallback = UrlLite.hostOf(url) ?? url;
    const site = new Site(newId(), name.trim() === '' ? fallback : name.trim(), url, Date.now());
    sites.push(site);
    this.save(sites);
    return site;
  }

  update(site: Site): void {
    const sites = this.load();
    for (let i = 0; i < sites.length; i++) {
      if (sites[i].id === site.id) {
        sites[i] = site;
        this.save(sites);
        return;
      }
    }
  }

  remove(id: string): void {
    const kept: Site[] = [];
    for (const s of this.load()) {
      if (s.id !== id) {
        kept.push(s);
      }
    }
    this.save(kept);
  }
}
