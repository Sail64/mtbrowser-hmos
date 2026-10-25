/**
 * 站点（书签）：浏览器内可访问地址的持久化入口。
 * 移植自 Android cn.tobe.mtbrowser.domain.model.Site（逐字段一致）。
 */
export class Site {
  id: string;
  name: string;
  url: string;
  /** epoch 毫秒（Android: Long createdAt） */
  createdAt: number;

  constructor(id: string, name: string, url: string, createdAt: number) {
    this.id = id;
    this.name = name;
    this.url = url;
    this.createdAt = createdAt;
  }
}
