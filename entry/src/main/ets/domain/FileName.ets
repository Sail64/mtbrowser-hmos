/**
 * 下载文件名规则（纯逻辑，零平台依赖）。
 *
 * 名字来自服务端 Content-Disposition，属于不可信输入：直接拼进文件路径就是路径穿越。
 * 所以「怎么取名」必须是 domain 的规则、必须能被冒烟覆盖，不能让 platform 层各写一遍。
 */

/** MIME → 兜底后缀（拿不到名字时用）。 */
export function extensionForMime(mimetype: string): string {
  const m = mimetype === null || mimetype === undefined ? '' : mimetype.toLowerCase();
  if (m.indexOf('pdf') >= 0) {
    return '.pdf';
  }
  if (m.indexOf('json') >= 0) {
    return '.json';
  }
  if (m.indexOf('zip') >= 0) {
    return '.zip';
  }
  if (m.indexOf('pkcs12') >= 0 || m.indexOf('x-pkcs') >= 0) {
    return '.p12';
  }
  if (m.indexOf('x-pem') >= 0 || m.indexOf('pkix-cert') >= 0) {
    return '.pem';
  }
  if (m.indexOf('image') >= 0) {
    return '.png';
  }
  if (m.indexOf('text') >= 0) {
    return '.txt';
  }
  return '.bin';
}

/**
 * 文件名消毒：只留 basename，去掉控制字符/路径分隔符/前导点，限长 120。
 * 返回空串表示"这个名字不可用"，调用方应换下一个候选。
 */
export function sanitizeFileName(raw: string): string {
  let name = raw === null || raw === undefined ? '' : raw.trim();
  // 两种分隔符都当路径处理（`..\..\x` 也拦得住）
  name = name.replace(/\\/g, '/');
  const slash = name.lastIndexOf('/');
  if (slash >= 0) {
    name = name.substring(slash + 1);
  }
  // 控制字符（含 NUL、换行）一律剔除
  name = name.replace(/[\u0000-\u001f\u007f]/g, '');
  // 去掉前导点：`.`、`..`、`..hidden` 都变成安全名字
  while (name.startsWith('.')) {
    name = name.substring(1);
  }
  name = name.trim();
  if (name === '') {
    return '';
  }
  if (name.length > 120) {
    const dot = name.lastIndexOf('.');
    const ext = dot > 0 && name.length - dot <= 10 ? name.substring(dot) : '';
    name = name.substring(0, 120 - ext.length) + ext;
  }
  return name;
}

/**
 * 从 Content-Disposition 推文件名，依次尝试：
 * filename*=UTF-8''xxx → filename="xxx" → URL 末段 → download + MIME 后缀。
 */
export function fileNameFrom(contentDisposition: string, url: string, mimetype: string): string {
  const cd = contentDisposition === null || contentDisposition === undefined ? '' : contentDisposition;
  const star = /filename\*\s*=\s*[^']*'[^']*'([^;]+)/i.exec(cd);
  if (star !== null) {
    try {
      const decoded = sanitizeFileName(decodeURIComponent(star[1].trim()));
      if (decoded !== '') {
        return decoded;
      }
    } catch (e) {
      // 编码异常就退到下一个候选
    }
  }
  const plain = /filename\s*=\s*"?([^";]+)"?/i.exec(cd);
  if (plain !== null) {
    const cleaned = sanitizeFileName(plain[1]);
    if (cleaned !== '') {
      return cleaned;
    }
  }
  const clean = url.split('?')[0].split('#')[0];
  const slash = clean.lastIndexOf('/');
  const base = slash >= 0 ? clean.substring(slash + 1) : clean;
  const stem = sanitizeFileName(base);
  if (stem !== '' && stem.indexOf('.') > 0) {
    return stem;
  }
  const ext = extensionForMime(mimetype);
  return stem === '' ? `download${ext}` : `${stem}${ext}`;
}