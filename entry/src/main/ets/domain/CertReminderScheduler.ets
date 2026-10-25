import { CertKind } from './model/CertModels';

/**
 * 证书提醒调度：决定「弹不弹」并记录已提醒状态。
 * 目标行为：同一 host + 证书类别每 24 小时最多提醒一次（持久化，重启不重置）。
 * （与 Android domain/CertReminderScheduler.kt 同源移植）
 */
export interface CertReminderScheduler {
  shouldRemind(host: string, kind: CertKind, now?: number): boolean;
  markReminded(host: string, kind: CertKind, now?: number): void;
}
