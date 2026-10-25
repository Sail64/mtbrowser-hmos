import { Site } from './model/Site';

/** 站点（书签）仓库：主页、收藏、按 host 查询的唯一数据源。 */
export interface SiteRepository {
  all(): Site[];
  byHost(host: string): Site | null;
  add(name: string, url: string): Site;
  update(site: Site): void;
  remove(id: string): void;
  findByUrl(url: string): Site | null;
}
