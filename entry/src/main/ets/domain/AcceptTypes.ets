/**
 * `<input type="file" accept="...">` 的翻译规则（纯逻辑，零平台依赖）。
 *
 * picker 的后缀过滤器只认扩展名，不认 MIME；反过来把 `*​/*` 翻译成 `.*` 会被当成
 * 字面匹配从而一个文件都不显示。所以这层翻译必须显式、可测，返回空数组 = 不加过滤。
 */
export function suffixFilters(acceptTypes: string[]): string[] {
  const out: string[] = [];
  for (const raw of acceptTypes) {
    const t = raw.trim().toLowerCase();
    if (t === '' || t === '*/*' || t === '*') {
      return [];
    }
    if (t.startsWith('image/')) {
      pushAll(out, ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic']);
    } else if (t.startsWith('video/')) {
      pushAll(out, ['.mp4', '.mov', '.mkv', '.webm', '.3gp']);
    } else if (t.startsWith('audio/')) {
      pushAll(out, ['.mp3', '.m4a', '.wav', '.aac', '.ogg', '.flac']);
    } else if (t === 'application/pdf') {
      pushAll(out, ['.pdf']);
    } else if (t === 'text/plain') {
      pushAll(out, ['.txt', '.log', '.md', '.csv']);
    } else if (t.startsWith('text/')) {
      pushAll(out, ['.txt', '.html', '.css', '.js', '.json', '.md']);
    } else if (t === 'application/json') {
      pushAll(out, ['.json']);
    } else if (t.indexOf('/') > 0) {
      // 其它 MIME 按子类型猜后缀：application/x-pkcs12 → .p12
      const sub = t.substring(t.indexOf('/') + 1);
      if (sub.length >= 2 && sub.length <= 5 && sub.indexOf('+') < 0) {
        pushAll(out, ['.' + sub]);
      }
    }
  }
  const uniq: string[] = [];
  for (const s of out) {
    if (uniq.indexOf(s) < 0) {
      uniq.push(s);
    }
  }
  return uniq;
}

function pushAll(dst: string[], items: string[]): void {
  for (const it of items) {
    dst.push(it);
  }
}