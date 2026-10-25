/**
 * ASN.1 时间字符串 → epoch 毫秒（纯字符串解析，零平台依赖）。
 * UTCTime: YYMMDDhhmmssZ（RFC 5280：YY>=50 视为 19YY，否则 20YY）
 * GeneralizedTime: YYYYMMDDhhmmssZ
 * 解析失败返回 null（调用方按「无法评估」处理，与 Android prober 失败静默同语义）。
 */
export function parseAsn1Time(str: string | null): number | null {
  if (str === null) {
    return null;
  }
  const s = str.trim();
  let year = -1;
  let rest = '';
  if (/^\d{12}Z$/.test(s)) {
    // UTCTime YYMMDDhhmmssZ
    const yy = parseInt(s.substring(0, 2), 10);
    year = yy >= 50 ? 1900 + yy : 2000 + yy;
    rest = s.substring(2);
  } else if (/^\d{14}Z$/.test(s)) {
    // GeneralizedTime YYYYMMDDhhmmssZ
    year = parseInt(s.substring(0, 4), 10);
    rest = s.substring(4);
  } else {
    return null;
  }
  const mm = parseInt(rest.substring(0, 2), 10);
  const dd = parseInt(rest.substring(2, 4), 10);
  const hh = parseInt(rest.substring(4, 6), 10);
  const mi = parseInt(rest.substring(6, 8), 10);
  const ss = parseInt(rest.substring(8, 10), 10);
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31 || hh > 23 || mi > 59 || ss > 60) {
    return null;
  }
  return Date.UTC(year, mm - 1, dd, hh, mi, ss % 60);
}
