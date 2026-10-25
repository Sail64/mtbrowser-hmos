/**
 * ArkWeb SslError 数字码 → 中文描述（文案 SSOT，对应 Android BrowserWebViewClient 里的
 * `when (error.primaryError)` 映射表）。
 *
 * ArkTS 的 domain 层不许 import @kit.ArkWeb，所以这里按 SDK 的枚举取值硬编码：
 *   Invalid = 0, HostMismatch = 1, DateInvalid = 2, Untrusted = 3
 * 未知码返回 null，由调用方决定兜底文案。
 */
export function sslErrorLabel(code: number): string | null {
  switch (code) {
    case 0:
      return '一般证书错误';
    case 1:
      return '证书与域名不匹配';
    case 2:
      return '证书日期无效（已过期或尚未生效）';
    case 3:
      return '证书不受信任';
    default:
      return null;
  }
}