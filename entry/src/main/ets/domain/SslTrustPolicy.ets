import type { DomainWhitelist } from './DomainWhitelist';

/**
 * SSL 放行决策。以 SSOT 为前提：谁能放行、放行多久，只有这一个地方说了算。
 *
 * 与 Android 的差异（诚实记录）：
 * - ArkWeb 的 SSL 错误事件不提供证书对象，所以这里没有 cert 参数，
 *   也无法区分"已过期 / 域名不匹配 / 不受信任"；具体原因由调用方经 errorKind 传入。
 * - 非白名单站点一律 DENY：白名单是主边界，边界外的站点连"仍要继续"的机会都不给。
 */

/** SSL 放行决策类型。 */
export enum SslDecisionKind {
  /** 无条件放行（如该 host 已有会话豁免）。 */
  PROCEED,
  /** 交给用户决策。 */
  ASK_USER,
  /** 直接拦截。 */
  DENY
}

/**
 * SSL 放行决策。Android 原实现用 sealed interface + data object/class 表达和类型；
 * ArkTS 无代数数据类型，用「kind 枚举 + 私有构造工厂」等价建模，调用侧必须 switch kind 全覆盖。
 */
export class SslDecision {
  readonly kind: SslDecisionKind;
  /** 仅 ASK_USER 有值：展示给用户的放行原因 */
  readonly reason: string;

  private constructor(kind: SslDecisionKind, reason: string) {
    this.kind = kind;
    this.reason = reason;
  }

  static proceed(): SslDecision {
    return new SslDecision(SslDecisionKind.PROCEED, '');
  }

  static askUser(reason: string): SslDecision {
    return new SslDecision(SslDecisionKind.ASK_USER, reason);
  }

  static deny(): SslDecision {
    return new SslDecision(SslDecisionKind.DENY, '');
  }
}

/**
 * SSL 放行策略：谁放行、放行多久，只有这一个地方说了算。
 * 会话级豁免仅保存在内存中，进程结束即失效（正派：不给永久跳过校验的机会）。
 * （与 Android domain/SslTrustPolicy.kt 同源移植）
 */
export interface SslTrustPolicy {
  onError(host: string, errorKind: string | null): SslDecision;
  grantSessionExemption(host: string): void;
  hasSessionExemption(host: string): boolean;
}

/**
 * 默认 SSL 放行策略：
 * - 已有会话豁免的 host 直接放行；
 * - 白名单外站点一律 DENY（不给用户"仍要继续"的机会）；
 * - 白名单内站点交用户决策（自签/过期内网站点不无路可走，但绝不静默放行）。
 */
export class DefaultSslTrustPolicy implements SslTrustPolicy {
  private whitelist: DomainWhitelist;
  private exemptions: Set<string> = new Set();

  constructor(whitelist: DomainWhitelist) {
    this.whitelist = whitelist;
  }

  onError(host: string, errorKind: string | null): SslDecision {
    if (this.hasSessionExemption(host)) {
      return SslDecision.proceed();
    }
    if (!this.whitelist.allows(`https://${host}/`)) {
      return SslDecision.deny();
    }
    // 只陈述确定的事实：ArkWeb 不给我们证书对象，别断言"证书无效"
    const reason = errorKind !== null ? `无法完成证书校验（${errorKind}）` : '无法完成证书校验';
    return SslDecision.askUser(reason);
  }

  grantSessionExemption(host: string): void {
    this.exemptions.add(host);
  }

  hasSessionExemption(host: string): boolean {
    return this.exemptions.has(host);
  }
}
