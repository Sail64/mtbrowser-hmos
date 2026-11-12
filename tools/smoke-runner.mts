/**
 * domain 层冒烟断言（与 Android 语义契约一一对应）。修改 domain/ 后必跑：sh tools/domain-smoke.sh
 * 覆盖：UrlLite / CertificateAdvisor / SslTrustPolicy / NavigationPolicy /
 *       DomainWhitelist / Asn1Time / kindLabel / ServerCertReminderService 编排（mock 端口）
 */
import { UrlLite } from './domain/UrlLite.ts';
import { DefaultCertificateAdvisor } from './domain/CertificateAdvisor.ts';
import { CertInfo, CertKind, CertVerdict, NavigationDecision, kindLabel } from './domain/model/CertModels.ts';
import { DefaultSslTrustPolicy, SslDecisionKind } from './domain/SslTrustPolicy.ts';
import { DefaultNavigationPolicy } from './domain/NavigationPolicy.ts';
import { DomainWhitelist } from './domain/DomainWhitelist.ts';
import { LocalNetwork } from './domain/LocalNetwork.ts';
import { shouldOpenInNewTab } from './domain/LinkOpenPolicy.ts';
import { BlockedCards } from './domain/BlockedCards.ts';
import { InterceptAction, decideIntercept } from './domain/InterceptDecision.ts';
import { fileNameFrom, sanitizeFileName, extensionForMime } from './domain/FileName.ts';
import { suffixFilters } from './domain/AcceptTypes.ts';
import { parseAsn1Time } from './domain/Asn1Time.ts';
import { ServerCertReminderService } from './domain/ServerCertReminderService.ts';
import type { CertificateSource, CertReminderNotifier } from './domain/ServerCertReminderService.ts';
import type { ProbeThrottle } from './domain/ProbeThrottle.ts';
import type { CertReminderScheduler } from './domain/CertReminderScheduler.ts';

let pass = 0, fail = 0;
function ok(cond: boolean, name: string) {
  if (cond) { pass++; } else { fail++; console.error('FAIL: ' + name); }
}
const DAY = 86400000;

// —— UrlLite ——
const p1 = UrlLite.parse('https://A.com:8080/Path?q=1#f');
ok(p1.scheme === 'https' && p1.host === 'a.com', 'url parse basic');
ok(UrlLite.parse('https://user@pass@host.cn/x').host === 'host.cn', 'userinfo strip');
ok(UrlLite.parse('https://a.com./x').host === 'a.com', 'trailing root dot');
ok(UrlLite.parse('mailto:x@y.z').scheme === 'mailto' && UrlLite.parse('mailto:x@y.z').host === null, 'mailto scheme no host');
ok(UrlLite.parse('not a url').scheme === null, 'relative/no-scheme');
ok(UrlLite.parse('https://[::1]:8080/x').host!.startsWith('[::1]'), 'ipv6 literal kept');
ok(UrlLite.parse('https://x.a.b.c/').host === 'x.a.b.c', 'subdomain');
ok(UrlLite.withHttpsPrefix('example.org') === 'https://example.org', 'prefix add');
ok(UrlLite.withHttpsPrefix('http://a') === 'http://a', 'prefix keep');
ok(UrlLite.withHttpsPrefix('  ') === '', 'prefix empty');
ok(UrlLite.parse('HTTPS://A.Example.COM:8443/x').host === 'a.example.com', 'uppercase scheme keeps host');
ok(UrlLite.originOf('https://a.example.com:8080/c/9985f5?x=1#y') === 'https://a.example.com:8080', 'origin keeps port, drops path/query/hash');
ok(UrlLite.originOf('https://a.com') === 'https://a.com', 'origin bare host');
ok(UrlLite.originOf('https://u:p@a.com:8/x') === 'https://a.com:8', 'origin strips userinfo');
ok(UrlLite.originOf('mailto:x@y.z') === null, 'origin null for non-hierarchical');
// 反斜杠必须当 authority 终止符，否则 `https://evil.com\@allowed.com/x` 会被判成 allowed.com
ok(UrlLite.parse('https://evil.com\\@allowed.com/x').host === 'evil.com', 'backslash ends authority (chromium parity)');
ok(UrlLite.parse('https://al\\lowed.com/x').host === 'al', 'backslash splits host like chromium');
ok(UrlLite.parse('https://a\t\n\r.com/x').host === 'a.com', 'tab/newline stripped');

// —— CertificateAdvisor ——
const adv = new DefaultCertificateAdvisor();
ok(adv.evaluate(new CertInfo('s', Date.now() - DAY), CertKind.CLIENT) === CertVerdict.EXPIRED, 'advisor expired');
ok(adv.evaluate(new CertInfo('s', Date.now() + 29 * DAY), CertKind.CLIENT) === CertVerdict.EXPIRING, 'advisor client 29d expiring');
ok(adv.evaluate(new CertInfo('s', Date.now() + 31 * DAY), CertKind.CLIENT) === CertVerdict.VALID, 'advisor client 31d valid');
ok(adv.evaluate(new CertInfo('s', Date.now() + 13 * DAY), CertKind.SERVER) === CertVerdict.EXPIRING, 'advisor server 13d expiring');
ok(adv.evaluate(new CertInfo('s', Date.now() + 15 * DAY), CertKind.SERVER) === CertVerdict.VALID, 'advisor server 15d valid');
ok(adv.message(CertVerdict.EXPIRING, CertKind.SERVER, 10).includes('将在 10 天后过期'), 'advisor message text');

// —— SslTrustPolicy（按白名单决定 DENY / ASK_USER）——
const wlSsl = new DomainWhitelist();
wlSsl.loadFrom('*.a.com\nb.com\n');
const policy = new DefaultSslTrustPolicy(wlSsl);
const d1 = policy.onError('a.com', '证书与域名不匹配');
ok(d1.kind === SslDecisionKind.ASK_USER && d1.reason.includes('无法完成证书校验'), 'ssl ask for whitelisted host');
ok(d1.reason.includes('证书与域名不匹配'), 'ssl reason carries errorKind');
policy.grantSessionExemption('a.com');
ok(policy.onError('a.com', '证书与域名不匹配').kind === SslDecisionKind.PROCEED, 'ssl exemption proceed');
ok(!policy.hasSessionExemption('b.com'), 'ssl exemption per-host');
ok(policy.onError('evil.com', '证书已过期').kind === SslDecisionKind.DENY,
  'ssl deny for non-whitelisted host (DENY 分支必须可达)');

// —— NavigationPolicy ——
const nav = new DefaultNavigationPolicy();
ok(nav.decide('https://a', null) === NavigationDecision.OPEN_IN_APP, 'nav https in-app');
ok(nav.decide('garbage', null) === NavigationDecision.OPEN_IN_APP, 'nav unparseable fallback in-app');
ok(nav.decide('mailto:a@b.c', null) === NavigationDecision.OPEN_EXTERNAL, 'nav mailto external');
ok(nav.decide('someapp://deeplink?x=1', null) === NavigationDecision.BLOCK, 'nav unknown scheme blocked');

// —— DomainWhitelist ——
const wl = new DomainWhitelist();
wl.loadFrom('# 注释\n\n*.a.com\nexact.b.com\n');
ok(wl.allows('https://a.com/x'), 'wl base match');
ok(wl.allows('https://x.a.com/y'), 'wl subdomain match');
ok(!wl.allows('https://notxa.com/'), 'wl no false subdomain');
ok(wl.allows('https://exact.b.com'), 'wl exact');
ok(!wl.allows('https://c.com'), 'wl deny others');
ok(wl.allows('about:blank'), 'wl non-http pass');
ok(wl.allows('HTTPS://X.A.COM/y'), 'wl uppercase scheme + host still matches');

// ---- 内网地址永远放行（白名单只挡公网误入） ----
const wlLocal = new DomainWhitelist();
wlLocal.loadFrom('*.a.com\n');
ok(wlLocal.allows('http://10.0.0.5:5000/'), 'local: 10/8 allowed without entry');
ok(wlLocal.allows('https://192.168.0.1/'), 'local: 192.168/16 allowed');
ok(wlLocal.allows('https://172.20.1.1:8443/x'), 'local: 172.16/12 allowed');
ok(wlLocal.allows('http://127.0.0.1:8080/'), 'local: loopback allowed');
ok(wlLocal.allows('http://nas:5000/'), 'local: single-label host allowed');
ok(wlLocal.allows('http://printer.local/'), 'local: mdns .local allowed');
ok(wlLocal.allows('http://[::1]:8080/'), 'local: ipv6 loopback allowed');
ok(!wlLocal.allows('https://172.32.0.1/'), 'public 172.32 still blocked');
ok(!wlLocal.allows('https://8.8.8.8/'), 'public ip still blocked');
ok(!wlLocal.allows('https://evil.example.org/'), 'public unknown host still blocked');

ok(LocalNetwork.isLocalHost('10.0.0.5'), 'ln 10/8');
ok(!LocalNetwork.isLocalHost('11.0.0.1'), 'ln 11.x is public');
ok(LocalNetwork.isLocalHost('172.31.255.255'), 'ln 172.31 upper bound');
ok(!LocalNetwork.isLocalHost('172.32.0.1'), 'ln 172.32 outside');
ok(LocalNetwork.isLocalHost('169.254.10.1'), 'ln link-local');
ok(!LocalNetwork.isLocalHost('example.com'), 'ln public domain');
ok(!LocalNetwork.isLocalHost(null), 'ln null');
ok(!LocalNetwork.isLocalHost(''), 'ln empty');

// —— 绕过面：任何"换种写法就变成公网"的输入都必须 fail-closed ——
ok(!LocalNetwork.isLocalHost('010.0.0.5'), 'ln leading-zero octet rejected (WHATWG reads as 8.0.0.5)');
ok(!wlLocal.allows('http://010.0.0.5/'), 'wl blocks octal-ambiguity ip');
ok(!LocalNetwork.isLocalHost('134744072'), 'ln decimal ip literal 8.8.8.8 rejected');
ok(!wlLocal.allows('http://134744072/'), 'wl blocks decimal ip literal that decodes to 8.8.8.8');
ok(!LocalNetwork.isLocalHost('0x08080808'), 'ln hex ip literal rejected');
ok(!wlLocal.allows('http://0x08080808/'), 'wl blocks hex ip literal');
ok(!LocalNetwork.isLocalHost('10.0.0.1.evil.com'), 'ln ip-prefixed public domain not local');
ok(!wlLocal.allows('http://10.0.0.1.evil.com/'), 'wl blocks ip-prefixed public domain');
ok(LocalNetwork.isLocalHost('[::ffff:10.0.0.1]'), 'ln ipv4-mapped private is local');
ok(!LocalNetwork.isLocalHost('[::ffff:8.8.8.8]'), 'ln ipv4-mapped public is not local');
ok(!wlLocal.allows('http://[::ffff:8.8.8.8]/'), 'wl blocks ipv4-mapped public');
ok(wlLocal.allows('http://10.0.0.1./'), 'wl allows private ip with trailing dot');
ok(!LocalNetwork.isLocalHost('127.1'), 'ln short-form loopback not guessed (fail-closed)');
ok(LocalNetwork.isLocalHost('nas'), 'ln single-label intranet name still allowed');
const wl2 = new DomainWhitelist();
wl2.loadFrom(null);
ok(!wl2.allows('https://anything.example.org'), 'wl missing file = deny all public hosts');
// 语义变更显式化：空名单也放行单标签内网短名（改测试不是为了让旧断言通过，而是把新语义写死）
ok(wl2.allows('http://nas'), 'wl missing file still allows single-label intranet host');

// —— Asn1Time ——
ok(parseAsn1Time('261231235959Z') === Date.UTC(2026, 11, 31, 23, 59, 59), 'asn1 utc');
ok(parseAsn1Time('500101000000Z') === Date.UTC(1950, 0, 1), 'asn1 yy50 = 1950');
ok(parseAsn1Time('20261231230000Z') === Date.UTC(2026, 11, 31, 23, 0, 0), 'asn1 generalized');
ok(parseAsn1Time('bad') === null && parseAsn1Time(null) === null, 'asn1 invalid null');

// —— kindLabel ——
ok(kindLabel(CertKind.CLIENT) === 'CLIENT' && kindLabel(CertKind.SERVER) === 'SERVER', 'kindLabel');

// —— ServerCertReminderService（mock 端口验证编排）——
class FakeSource implements CertificateSource {
  cert: CertInfo | null = null;
  async currentServerCert(): Promise<CertInfo | null> { return this.cert; }
}
class MemThrottle implements ProbeThrottle {
  map = new Map<string, number>();
  shouldRun(host: string, now?: number): boolean {
    const last = this.map.get(host); const t = now ?? Date.now();
    return last === undefined || t - last >= DAY;
  }
  markRun(host: string, now?: number): void { this.map.set(host, now ?? Date.now()); }
}
class MemReminders implements CertReminderScheduler {
  map = new Map<string, number>();
  shouldRemind(host: string, kind: CertKind, now?: number): boolean {
    const t = now ?? Date.now(); const last = this.map.get(kindLabel(kind) + ':' + host);
    return last === undefined || t - last >= DAY;
  }
  markReminded(host: string, kind: CertKind, now?: number): void {
    this.map.set(kindLabel(kind) + ':' + host, now ?? Date.now());
  }
}
class Recorder implements CertReminderNotifier {
  msgs: string[] = [];
  show(m: string): void { this.msgs.push(m); }
}

const fake = new FakeSource();
const nc = new Recorder();
const svc = new ServerCertReminderService(fake, adv, new MemThrottle(), new MemReminders(), nc);
svc.onPageEnd('https://a.com/x'); await new Promise(r => setTimeout(r, 10));
ok(nc.msgs.length === 0, 'reminder silent when no cert');
fake.cert = new CertInfo('s', Date.now() - DAY); // 过期
svc.onPageEnd('https://a.com/y'); await new Promise(r => setTimeout(r, 10));
ok(nc.msgs.length === 1 && nc.msgs[0].includes('已过期'),
  'null cert must not burn the throttle window; retry fires reminder');
svc.onPageEnd('https://a.com/again'); await new Promise(r => setTimeout(r, 10));
ok(nc.msgs.length === 1, 'reminder throttled after a successful probe');
svc.onPageEnd('https://b.com/'); await new Promise(r => setTimeout(r, 10));
ok(nc.msgs.length === 2 && nc.msgs[1].includes('已过期'), 'reminder fires once for new host');
fake.cert = new CertInfo('s', Date.now() + 100 * DAY);
svc.onPageEnd('https://c.com/'); await new Promise(r => setTimeout(r, 10));
ok(nc.msgs.length === 2, 'valid cert no reminder');

// —— TabList（标签生命周期 + LRU，纯逻辑）——
import { TabList, EMPTY_TAB_TITLE } from './domain/TabList.ts';

let nowMs = 1000;
const clock = (): number => nowMs;
const tl = new TabList(3, clock);

ok(tl.size() === 0 && tl.currentId() === -1, 'tablist empty starts');
const n1 = tl.newTab('https://a.com');
ok(n1.tab.id === 1 && tl.size() === 1 && tl.currentId() === 1, 'tablist new tab becomes current');
ok(n1.evicted.length === 0, 'tablist no eviction under limit');

nowMs = 2000;
const n2 = tl.newTab('https://b.com');
nowMs = 3000;
const n3 = tl.newTab('https://c.com');
ok(tl.size() === 3 && tl.currentId() === n3.tab.id, 'tablist fills to max');

// 切换回最老的 a 标签并选中它 → 淘汰应挑 b（lastUsedAt 最老且非 current）
nowMs = 4000;
ok(tl.select(n1.tab.id), 'tablist select existing');
ok(tl.currentId() === n1.tab.id, 'tablist select sets current');
nowMs = 5000;
const n4 = tl.newTab('https://d.com');
ok(n4.evicted.length === 1 && n4.evicted[0] === n2.tab.id, 'tablist evicts LRU non-current');
ok(tl.size() === 3 && tl.currentId() === n4.tab.id, 'tablist stays at max after evict');
ok(tl.find(n2.tab.id) === null, 'tablist evicted tab gone');

// 关闭当前标签 → 继任者优先右侧邻居
const tl2 = new TabList(4, clock);
const a = tl2.newTab('https://a').tab;
const b = tl2.newTab('https://b').tab;
const c = tl2.newTab('https://c').tab;
ok(tl2.select(b.id) && tl2.close(b.id) === c.id, 'tablist close picks right neighbour');
ok(tl2.close(c.id) === a.id, 'tablist close last picks left neighbour');
ok(tl2.close(a.id) === -1 && tl2.size() === 0, 'tablist close all resets current');

// 关闭非当前标签不影响 current
const tl3 = new TabList(4, clock);
const x = tl3.newTab('https://x').tab;
const y = tl3.newTab('https://y').tab;
ok(tl3.currentId() === y.id && tl3.close(x.id) === y.id, 'tablist close inactive keeps current');

// 关闭其他
const tl4 = new TabList(4, clock);
const p = tl4.newTab('https://p').tab;
tl4.newTab('https://q');
tl4.newTab('https://r');
const closed = tl4.closeOthers(p.id);
ok(closed.length === 2 && tl4.size() === 1 && tl4.currentId() === p.id, 'tablist closeOthers');

// 元信息：url/title 更新与展示文案
const tl5 = new TabList(2, clock);
const t1 = tl5.newTab().tab;
ok(t1.displayTitle() === EMPTY_TAB_TITLE && t1.displayUrl() === '空白页', 'tablist blank tab labels');
tl5.update(t1.id, 'https://a.com/x');
tl5.rename(t1.id, 'A 站');
const t1b = tl5.current()!;
ok(t1b.url === 'https://a.com/x' && t1b.displayTitle() === 'A 站', 'tablist update url+title');
tl5.update(t1.id, '');
ok(tl5.current()!.url === 'https://a.com/x', 'tablist update ignores empty url');
tl5.rename(t1.id, '');
ok(tl5.current()!.displayTitle() === 'https://a.com/x', 'tablist rename to empty falls back to url');
tl5.setProgress(t1.id, 42);
ok(tl5.progressOf(t1.id) === 42 && tl5.progressOf(999) === 0, 'tablist per-tab progress');
tl5.rename(t1.id, '改名');
ok(tl5.current()!.displayTitle() === '改名', 'tablist rename');
t1b.url = 'https://only-url.com';
t1b.title = '';
ok(t1b.displayTitle() === 'https://only-url.com', 'tablist falls back to url when no title');
ok(!tl5.select(999), 'tablist select unknown id false');

// —— SslError 文案映射 ——
import { sslErrorLabel } from './domain/SslErrorLabels.ts';
ok(sslErrorLabel(1) === '证书与域名不匹配', 'ssl label host mismatch');
ok(sslErrorLabel(2)!.includes('日期无效'), 'ssl label date invalid');
ok(sslErrorLabel(3) === '证书不受信任', 'ssl label untrusted');
ok(sslErrorLabel(99) === null, 'ssl label unknown null');

// —— NavigationPolicy：危险 scheme 必须 BLOCK（与安卓的有意偏离）——
ok(nav.decide('file:///etc/passwd', null) === NavigationDecision.BLOCK, 'nav file blocked');
ok(nav.decide('javascript:alert(1)', null) === NavigationDecision.BLOCK, 'nav javascript blocked');
ok(nav.decide('data:text/html,x', null) === NavigationDecision.BLOCK, 'nav data blocked');
ok(nav.decide('blob:https://a.com/uuid', null) === NavigationDecision.BLOCK, 'nav blob blocked');
ok(nav.decide('about:blank', null) === NavigationDecision.OPEN_IN_APP, 'nav about:blank allowed (internal blank page)');
ok(nav.decide('about:config', null) === NavigationDecision.BLOCK, 'nav other about: blocked');
ok(nav.decide('tel:12345', null) === NavigationDecision.OPEN_EXTERNAL, 'nav tel external');

// —— BookmarkService：保存唯一入口 ——
import { BookmarkService, SaveOutcome } from './domain/BookmarkService.ts';
import { Site } from './domain/model/Site.ts';
import type { SiteRepository } from './domain/SiteRepository.ts';

class MemSiteRepo implements SiteRepository {
  list: Site[] = [];
  private seq = 0;
  all(): Site[] { return this.list.slice(); }
  byHost(host: string): Site | null {
    for (const s of this.list) { if (UrlLite.hostOf(s.url) === host) { return s; } }
    return null;
  }
  add(name: string, url: string): Site {
    this.seq++;
    const s = new Site(`id${this.seq}`, name, url, 1000 + this.seq);
    this.list.push(s);
    return s;
  }
  update(site: Site): void {
    for (let i = 0; i < this.list.length; i++) { if (this.list[i].id === site.id) { this.list[i] = site; return; } }
  }
  remove(id: string): void { this.list = this.list.filter((s) => s.id !== id); }
  findByUrl(url: string): Site | null {
    for (const s of this.list) { if (s.url === url) { return s; } }
    return null;
  }
}

const repo = new MemSiteRepo();
const wlBm = new DomainWhitelist();
wlBm.loadFrom('*.ok.com\n');
const bm = new BookmarkService(repo, wlBm);

const r1 = bm.save(null, '', 'ok.com');
ok(r1.outcome === SaveOutcome.SAVED && r1.site!.name === 'ok.com', 'bookmark add falls back to host name');
ok(r1.site!.url === 'https://ok.com', 'bookmark add normalises scheme');
ok(r1.outsideWhitelist === false, 'bookmark add inside whitelist flag');

const r2 = bm.save(null, 'dupe', 'https://ok.com');
ok(r2.outcome === SaveOutcome.UPDATED && repo.all().length === 1, 'bookmark duplicate returns existing without insert');

const r3 = bm.save(null, 'evil', 'https://evil.com');
ok(r3.outcome === SaveOutcome.SAVED && r3.outsideWhitelist === true, 'bookmark outside whitelist flagged but saved');

const r4 = bm.save(null, 'x', '   ');
ok(r4.outcome === SaveOutcome.EMPTY_URL && r4.site === null, 'bookmark empty url rejected');

// 内网地址不该被白名单判定为"外面"：书签不应提示"访问会被拦截"
const rIntra = bm.save(null, 'nas', 'http://10.0.0.5:5000');
ok(rIntra.outcome === SaveOutcome.SAVED && rIntra.outsideWhitelist === false,
  'bookmark on private ip is not flagged outside whitelist');

const existing = r1.site!;
const r5 = bm.save(existing, '改名', 'https://ok.com/path');
ok(r5.outcome === SaveOutcome.UPDATED && r5.site!.name === '改名', 'bookmark update rewrites name');
ok(r5.site!.createdAt === existing.createdAt && r5.site!.id === existing.id, 'bookmark update keeps id/createdAt');

// —— FileName：下载文件名（服务端可控，必须防穿越） ——
ok(sanitizeFileName('../../etc/passwd') === 'passwd', 'filename strips traversal');
ok(sanitizeFileName('..\\..\\win.ini') === 'win.ini', 'filename strips windows traversal');
ok(sanitizeFileName('/abs/path/a.pdf') === 'a.pdf', 'filename strips leading dirs');
ok(sanitizeFileName('a\u0000b\n.txt') === 'ab.txt', 'filename strips control chars');
ok(sanitizeFileName('..') === '' && sanitizeFileName('.hidden') === 'hidden', 'filename dot handling');
ok(sanitizeFileName('x'.repeat(300)).length <= 200, 'filename ascii capped');
ok(sanitizeFileName('发'.repeat(100)).length < 100, 'filename cjk capped by bytes');
ok(sanitizeFileName('发票\u202Eexe.txt') === '发票exe.txt', 'filename strips bidi override');
ok(fileNameFrom('attachment; filename="report.pdf"', 'https://h/x', 'application/pdf') === 'report.pdf', 'cd plain');
ok(fileNameFrom("attachment; filename*=UTF-8''%E4%B8%AD%E6%96%87.pdf", 'https://h/x', 'application/pdf') === '中文.pdf', 'cd rfc5987');
ok(fileNameFrom('', 'https://h/dir/file.zip?sig=1', 'application/zip') === 'file.zip', 'url basename');
ok(fileNameFrom('', 'https://h/', 'application/pdf') === 'download.pdf', 'fallback by mime');
ok(extensionForMime('application/x-pkcs12') === '.p12', 'mime p12');

// —— AcceptTypes：accept 翻译 ——
ok(suffixFilters(['*/*']).length === 0, 'accept wildcard = no filter');
ok(suffixFilters(['image/*']).indexOf('.png') >= 0, 'accept image');
ok(suffixFilters(['application/pdf']).join(',') === '.pdf', 'accept pdf');
ok(suffixFilters(['image/png', 'image/*']).length === 7, 'accept dedupe');

// —— FabGeometry：悬浮按钮边界规则 ——
import { FabGeometry, FAB_UNSET } from './domain/FabGeometry.ts';
const c1 = FabGeometry.clamp(-30, -50, 360, 640, 36);
ok(c1.x === 0 && c1.y === 0, 'fab clamp negative to zero');
const c2 = FabGeometry.clamp(999, 999, 360, 640, 36);
ok(c2.x === 324 && c2.y === 604, 'fab clamp overflow to container minus size');
const c3 = FabGeometry.clamp(100, 100, 0, 0, 36);
ok(c3.x === 0 && c3.y === 0, 'fab clamp unknown container returns origin');
const fd1 = FabGeometry.defaultTopRight(360, 640, 36, 10);
ok(fd1.x === 314 && fd1.y === 10, 'fab default position top right');
const fd2 = FabGeometry.defaultTopRight(0, 0, 36, 10);
ok(fd2.x === FAB_UNSET && fd2.y === FAB_UNSET, 'fab default unset when container unknown');
ok(!FabGeometry.isSet(FAB_UNSET, 10) && FabGeometry.isSet(0, 0), 'fab isSet semantics');


// —— LinkOpenPolicy：链接点击是否另开标签 ——
const baseLink = {
  isMainFrame: true, isRequestGesture: true, isRedirect: false,
  method: 'GET', url: 'https://b.example.org/x', currentUrl: 'https://a.example.org/'
};
ok(shouldOpenInNewTab(baseLink), 'link: user click on http(s) opens new tab');
ok(!shouldOpenInNewTab({ ...baseLink, isRequestGesture: false }),
  'link: script navigation (no gesture) stays in current tab');
ok(!shouldOpenInNewTab({ ...baseLink, isRedirect: true }),
  'link: redirect chain stays in same tab');
ok(!shouldOpenInNewTab({ ...baseLink, method: 'POST' }),
  'link: form POST stays in current tab');
ok(!shouldOpenInNewTab({ ...baseLink, method: 'post' }),
  'link: lowercase post also rejected');
ok(!shouldOpenInNewTab({ ...baseLink, isMainFrame: false }),
  'link: iframe/subresource does not split tabs');
ok(!shouldOpenInNewTab({ ...baseLink, url: 'mailto:a@example.org' }),
  'link: mailto does not open a tab');
ok(!shouldOpenInNewTab({ ...baseLink, url: 'about:blank' }),
  'link: about:blank does not open a tab');
ok(!shouldOpenInNewTab({ ...baseLink, url: 'javascript:alert(1)' }),
  'link: javascript: does not open a tab');
ok(!shouldOpenInNewTab({ ...baseLink, url: 'https://a.example.org/#top' }),
  'link: same-page anchor (hash only) stays');
ok(!shouldOpenInNewTab({ ...baseLink, url: 'https://a.example.org/#other', currentUrl: 'https://a.example.org/#top' }),
  'link: hash-only change between anchors stays');
ok(shouldOpenInNewTab({ ...baseLink, url: 'https://a.example.org/page2' }),
  'link: different path same origin opens new tab');
ok(shouldOpenInNewTab({ ...baseLink, currentUrl: '' }),
  'link: empty current url still opens new tab');
ok(shouldOpenInNewTab({ ...baseLink, method: undefined as unknown as string }),
  'link: undefined method treated as GET');


// —— LinkOpenPolicy 补充边界（ArkWeb 可能给出的奇怪输入）——
ok(shouldOpenInNewTab({ ...baseLink, url: 'HTTPS://b.example.org/x' }),
  'link: uppercase scheme still opens new tab');
ok(!shouldOpenInNewTab({ ...baseLink, currentUrl: 'about:blank', url: 'about:blank' }),
  'link: blank current + blank target stays');
ok(shouldOpenInNewTab({ ...baseLink, currentUrl: 'about:blank' }),
  'link: real url from blank page opens new tab');
ok(!shouldOpenInNewTab({ ...baseLink, isRedirect: true, method: 'POST' }),
  'link: redirect+post still stays');
ok(shouldOpenInNewTab({ ...baseLink, url: '  https://b.example.org/x  ' }),
  'link: surrounding whitespace tolerated');

// —— InterceptDecision：顺序即安全语义 ——
const linkFacts = {
  isMainFrame: true, isRequestGesture: true, isRedirect: false,
  method: 'GET', url: 'https://b.example.org/x', currentUrl: 'https://a.example.org/'
};
ok(decideIntercept(NavigationDecision.OPEN_EXTERNAL, true, linkFacts) === InterceptAction.OPEN_EXTERNAL,
  'intercept: external scheme wins over everything');
ok(decideIntercept(NavigationDecision.BLOCK, false, linkFacts) === InterceptAction.BLOCK_SCHEME,
  'intercept: dangerous scheme blocked even for non-whitelisted host');
ok(decideIntercept(NavigationDecision.OPEN_IN_APP, false, linkFacts) === InterceptAction.BLOCK_WHITELIST,
  'intercept: whitelist check runs BEFORE split');
ok(decideIntercept(NavigationDecision.OPEN_IN_APP, true, linkFacts) === InterceptAction.NEW_TAB,
  'intercept: allowed + gesture link splits');
ok(decideIntercept(NavigationDecision.OPEN_IN_APP, true, { ...linkFacts, isRequestGesture: false }) === InterceptAction.LOAD,
  'intercept: allowed but script nav loads in place');
ok(decideIntercept(NavigationDecision.OPEN_IN_APP, true, { ...linkFacts, isMainFrame: false }) === InterceptAction.LOAD,
  'intercept: subframe loads in place (never splits)');
ok(decideIntercept(NavigationDecision.OPEN_IN_APP, true, { ...linkFacts, isMainFrame: false, isRequestGesture: true }) !== InterceptAction.BLOCK_WHITELIST,
  'intercept: subframe is never whitelist-blocked');

// —— BlockedCards：两个状态必须分开（活页面不许被持久化成空串）——
const bc = new BlockedCards();
bc.block(1, 'https://evil.example/', false);
ok(bc.cardUrlOf(1) === 'https://evil.example/', 'cards: initiate-block shows card');
ok(!bc.isUnloaded(1), 'cards: initiate-block does NOT mark unloaded');
ok(bc.persistedUrlOf(1, 'https://alive.example/page') === 'https://alive.example/page',
  'cards: live page keeps its URL when persisted (regression)');
bc.block(2, 'https://evil2.example/', true);
ok(bc.isUnloaded(2) && bc.persistedUrlOf(2, 'https://evil2.example/') === '',
  'cards: committed-block persists empty url');

// 关掉卡片后不许复活
bc.dismiss(1);
ok(bc.cardUrlOf(1) === '', 'cards: dismiss hides card');
ok(bc.cardUrlOf(2) === 'https://evil2.example/', 'cards: dismiss is per-tab');
// 关掉卡片不改变「文档已卸载」这一事实
ok(bc.persistedUrlOf(2, 'https://evil2.example/') === '', 'cards: dismiss keeps unloaded fact');

// 切标签回来（读 cardUrlOf）不再复活
ok(bc.cardUrlOf(1) === '', 'cards: no revive after dismiss + tab switch');

// 真正导航 / 页面加载成功 / 关标签
bc.block(3, 'https://evil3.example/', true);
bc.navigate(3);
ok(!bc.isUnloaded(3) && bc.persistedUrlOf(3, 'https://ok.example/') === 'https://ok.example/',
  'cards: navigate clears unloaded + card');
bc.block(4, 'https://evil4.example/', true);
bc.pageEnd(4);
ok(!bc.hasCard(4) && !bc.isUnloaded(4), 'cards: pageEnd clears both');
bc.block(5, 'https://evil5.example/', true);
bc.forget(5);
ok(!bc.hasCard(5) && !bc.isUnloaded(5) && bc.cardUrlOf(5) === '', 'cards: forget clears both (close/evict)');

console.log(`SMOKE RESULT: pass=${pass} fail=${fail}`);
if (fail > 0) { process.exit(1); }
