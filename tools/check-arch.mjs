// 架构守卫：机械化检查依赖方向，防止分层腐烂。
// 用法: node tools/check-arch.mjs   (违规时 exit 1 并列出位置)
//
// 规则（与 AGENTS.md 的依赖图一一对应）：
// R1 domain/**  只允许 import domain 内部相对路径；禁止任何平台包（@ohos./@kit./@internal/lib）
// R2 data/** platform/**  禁止 import ui/pages 和 app/entryability（下层不知道上层）
// R3 ui/** pages/**  禁止 import data 和 platform（UI 只面向 domain 类型 + AppGraph）
// R4 app/** entryability/** 组合根特权：允许全部
//
// 注意：pages/ 与 entryability/ 虽不在传统四层里，仍必须被检查——
// 漏检查等于给"把业务塞进页面文件"开了后门。

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = new URL('..', import.meta.url).pathname;
const ETS = join(ROOT, 'entry/src/main/ets');

const LAYERS = ['domain', 'data', 'platform', 'ui', 'pages', 'entryability', 'app'];

// 显式允许矩阵：任何不在矩阵里的 (from → to) 一律违规。
// 用矩阵而不是三个 if：新增层时忘了写规则，这里会 fail-closed 报出来，而不是悄悄放过。
const RULES = {
  domain: ['domain'],
  data: ['domain', 'data'],
  platform: ['domain', 'platform'],
  // ui 可以直接用 platform 适配器（文件选择、下载、Cookie 落盘这类 ArkWeb/OS 能力），
  // 因为两者都是"平台面"的层；但 ui 仍然不许碰 data，业务状态必须经 domain/app。
  ui: ['domain', 'platform', 'ui', 'app'],
  pages: ['domain', 'ui', 'pages', 'app'],
  // 组合根：允许全部（它就是装配点）
  entryability: ['domain', 'data', 'platform', 'ui', 'pages', 'app'],
  app: ['domain', 'data', 'platform', 'ui', 'pages', 'app'],
};

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (/\.(ets|ts)$/.test(name)) yield p;
  }
}

/**
 * 三种 import 形态都要抓，漏一种就等于给 domain 留后门：
 *   import { a } from 'x'  ⁄  export … from 'x'   （静态具名）
 *   import 'x'                                    （副作用导入）
 *   import('x')                                   （动态导入）
 */
const IMPORT_PATTERNS = [
  /(?:^|\n)\s*(?:import|export)\s+(?:[\s\S]*?)\s*from\s+['"]([^'"]+)['"]/g,
  /(?:^|\n)\s*import\s+['"]([^'"]+)['"]/g,
  /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
];

const violations = [];
for (const file of walk(ETS)) {
  const rel = relative(ETS, file).replaceAll('\\', '/');
  const top = rel.split('/')[0];
  if (!LAYERS.includes(top)) {
    // fail-closed：新增顶层目录必须先登记规则，否则等于开了个不被检查的后门
    violations.push(`${rel}: 未登记的顶层目录 '${top}'，请在 tools/check-arch.mjs 的 RULES 中登记`);
    continue;
  }
  const src = readFileSync(file, 'utf8');
  const checkSpec = (spec, index) => {
    const line = src.slice(0, index).split('\n').length;
    const at = `${rel}:${line}`;
    const isPkg = !spec.startsWith('.');
    if (isPkg) {
      // 平台包（@kit./@ohos.）只允许非 domain 层引用
      if (top === 'domain') {
        violations.push(`R1 ${at}: domain 禁止依赖平台包 '${spec}'（domain 必须零平台依赖）`);
      }
      return;
    }
    const norm = join(file, '..', spec).replaceAll('\\', '/');
    const r = relative(ETS, norm);
    let target = 'other';
    for (const l of LAYERS) {
      if (r.startsWith(l + '/') || r === l) target = l;
    }
    const allowed = RULES[top] || [];
    if (target === 'other' || allowed.indexOf(target) < 0) {
      violations.push(
        `R${top} ${at}: ${top} → ${target} 不在允许矩阵内（'${spec}'）；允许目标: ${allowed.join(', ')}`
      );
    }
  };
  for (const re of IMPORT_PATTERNS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(src)) !== null) {
      checkSpec(m[1], m.index);
    }
  }
}

if (violations.length) {
  console.error(`架构检查失败，${violations.length} 处违规:`);
  for (const v of violations) console.error('  ' + v);
  process.exit(1);
}
console.log('check-arch: 依赖方向全部合规');
