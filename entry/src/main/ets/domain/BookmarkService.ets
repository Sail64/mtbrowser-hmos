import { Site } from './model/Site';
import type { SiteRepository } from './SiteRepository';
import { UrlLite } from './UrlLite';
import type { DomainWhitelist } from './DomainWhitelist';

/** 收藏保存结果。 */
export enum SaveOutcome {
  /** 新建成功 */
  SAVED,
  /** 该 URL 已存在（未重复插入，返回已有站点） */
  UPDATED,
  /** 地址为空/非法 */
  EMPTY_URL
}

export class SaveResult {
  outcome: SaveOutcome;
  site: Site | null;
  /** 该地址不在域名白名单内：仍允许收藏，但调用方必须提示（否则等于埋一个打不开的书签） */
  outsideWhitelist: boolean;

  constructor(outcome: SaveOutcome, site: Site | null, outsideWhitelist: boolean) {
    this.outcome = outcome;
    this.site = site;
    this.outsideWhitelist = outsideWhitelist;
  }
}

/**
 * 收藏（书签）保存的唯一入口：URL 规范化、去重、白名单提示都在这里。
 *
 * 对应 Android 的两处重复实现（MainActivity.bookmarkCurrentPage 与 HomeView.save）——
 * 鸿蒙版合并为一处，避免"主页添加"和"浏览页收藏"出现不同文案/不同校验。
 */
export class BookmarkService {
  private repo: SiteRepository;
  private whitelist: DomainWhitelist;

  constructor(repo: SiteRepository, whitelist: DomainWhitelist) {
    this.repo = repo;
    this.whitelist = whitelist;
  }

  save(existing: Site | null, name: string, rawUrl: string): SaveResult {
    const url = UrlLite.withHttpsPrefix(rawUrl);
    if (url === '') {
      return new SaveResult(SaveOutcome.EMPTY_URL, null, false);
    }
    const outsideWhitelist = !this.whitelist.allows(url);
    const finalName = name.trim() !== '' ? name.trim() : (UrlLite.hostOf(url) ?? url);

    if (existing === null) {
      const dup = this.repo.findByUrl(url);
      if (dup !== null) {
        // 已收藏过同一 URL：不重复插入，直接返回已有项（避免书签列表出现两条一样的）
        return new SaveResult(SaveOutcome.UPDATED, dup, outsideWhitelist);
      }
      const added = this.repo.add(finalName, url);
      return new SaveResult(SaveOutcome.SAVED, added, outsideWhitelist);
    }
    const updated = new Site(existing.id, finalName, url, existing.createdAt);
    this.repo.update(updated);
    return new SaveResult(SaveOutcome.UPDATED, updated, outsideWhitelist);
  }
}