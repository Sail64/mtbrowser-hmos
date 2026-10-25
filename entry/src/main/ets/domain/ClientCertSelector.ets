/**
 * 客户端证书选择：按 host 隔离的凭据缓存与选择入口。
 * 平台细节（Android KeyChain / 鸿蒙 DeviceCertificateKit）由实现隐藏，业务层只面向该接口。
 *
 * 概念映射：
 * - Android 的 identity = keystore alias（字符串）
 * - 鸿蒙的 identity = certificateManager 凭据 keyUri（'ohos.account.keyUri://…' 形态字符串）
 * 两者都是"按 host 缓存的、可直接用于握手重放的凭据句柄"，故沿用同一抽象。
 */
/** 纯缓存端口（data 层实现），与「选择交互」拆开——Android 版让 store 对 chooseAlias throw 是坏味道，鸿蒙版不再继承。 */
export interface ClientCertIdentityStore {
  /** 该 host 上次选择并缓存的凭据 identity；无缓存返回 null */
  cachedIdentity(host: string): string | null;
  saveIdentity(host: string, identity: string): void;
  clearIdentity(host: string): void;
}

export interface ClientCertSelector extends ClientCertIdentityStore {
  /**
   * 拉起系统凭据选择交互。实现方负责在用户选择后写缓存。
   * callback 收到 identity；用户取消/失败收到 null。
   */
  chooseIdentity(host: string, port: number, callback: (identity: string | null) => void): void;
}
