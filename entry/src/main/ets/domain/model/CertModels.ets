/**
 * 证书领域模型。屏蔽具体证书 API 差异：
 * adapter（ArkWeb X509Cert / certManager CMResult）在入口处转成本文件的结构，
 * domain 之上只见到这里，不感知平台证书类型。
 */

/** 证书类别：客户端证书（mTLS 出示的）或服务端证书。 */
export enum CertKind {
  CLIENT,
  SERVER
}

/** ArkTS enum 无 .name：存储 key 前缀等场景用此函数（对应 Android kind.name）。 */
export function kindLabel(kind: CertKind): string {
  return kind === CertKind.CLIENT ? 'CLIENT' : 'SERVER';
}

/** 证书健康度结论。 */
export enum CertVerdict {
  VALID,
  EXPIRING,
  EXPIRED
}

/** 导航决策：一个 URL 应该在哪里打开。 */
export enum NavigationDecision {
  OPEN_IN_APP,
  OPEN_EXTERNAL,
  /** 危险 scheme（file:/javascript:/data:/blob:/content:/about:）：不外抛、不加载，直接拦掉 */
  BLOCK
}

/** 证书快照（平台无关）。notAfterMs 为 epoch 毫秒。 */
export class CertInfo {
  subject: string;
  notAfterMs: number;

  constructor(subject: string, notAfterMs: number) {
    this.subject = subject;
    this.notAfterMs = notAfterMs;
  }
}
