# mtbrowser-hmos 架构说明

> 本文件原计划放 AGENTS.md（自动被编码 agent 加载），因该文件名受写保护需逐项批准，改放此处。
> **依赖方向由 `tools/check-arch.mjs` 机械强制，违规 exit 1。**

Android 版 `code/mtbrowser` 的 HarmonyOS NEXT 移植。

**真机验证过（HarmonyOS 7.0 / API 26）**：书签主页增删、单标签浏览、mTLS 客户端证书握手（`a.example.com:8443` 实测 200）、SSL 错误弹窗放行、服务端证书过期提醒、域名白名单拦截、Hermes WebUI（SPA）正常交互。

**已实现但只在编译/静态层验证，尚未上真机**：多标签（LRU 4）与概览层、加载进度条、标题同步、收藏完整流程、HTTP 400 证书清理、302 重定向白名单兜底、SPA pushState URL 同步、危险 scheme 拦截。

**未做**：状态栏染色（页面背景色联动）、书签跨端导入。

**深色模式**：只开 `darkMode(Auto)`，**不开** `forceDarkAccess`——实测强制反色会把 LibreChat 整页打成白屏（HTTP 200、无 JS 报错），与 Android `FORCE_DARK_AUTO` 效果不可类比。缺口清单与顺序见本文件末节。

## 构建与检查命令（无头，不依赖 IDE）

```bash
cd ~/code/mtbrowser-hmos
devecocli build                 # 产出 entry/build/default/outputs/default/*.hap
node tools/check-arch.mjs       # 架构守卫（每次提交前必跑）
devecocli check arkts entry/src/main/ets/<file>.ets   # 单文件 ArkTS 静态检查
```

签名需先 `devecocli auth login`（华为开发者账号，一次性），之后 `devecocli signature generate`。

## 架构铁律（违反 = 腐烂的开始）

依赖方向：

```
ui ──→ app(组合根) ──→ data / platform ──→ domain
domain：零平台依赖，禁止 import 任何 @ohos.* / @kit.*
```

1. **`domain/` 不 import 任何 `@ohos.*` / `@kit.*` / `lib*`。** 平台类型（Context、WebResourceRequest、X509Cert、preferences）一律止步于 data/platform 边界；进 domain 的只有转换后的自有模型（`CertInfo`、`Site`、字符串、毫秒数）。
2. **所有业务规则住 domain，UI 事件回调里不写规则。** ArkWeb 的 `onLoadIntercept` / `onSslErrorEventReceive` / `onClientAuthenticationRequest` 只负责：提取参数 → 问 domain → 执行 domain 的决策。新增功能先问「决策逻辑住 domain 哪个文件」，再问「adapter 怎么接」。
3. **单一事实来源（SSOT），与 Android 版同源：**
   - 证书健康度/文案 → `domain/CertificateAdvisor.ets`（不许别处算天数）
   - 放行与否 → `domain/SslTrustPolicy.ets`
   - 在哪打开 → `domain/NavigationPolicy.ets`
   - 主框架准入 → `domain/DomainWhitelist.ets`
   - 提醒去重 → `domain/CertReminderScheduler.ets`（接口）
   - 标签生命周期 / LRU / 关闭选邻居 → `domain/TabList.ets`（UI 只按返回的 id 建销 Web 实例）
4. **`ui/` 只经 `app/AppGraph.ets` 拿实现**，不 new platform/data 的类、不 import 它们。将来换实现（mock repository 做测试等）只改 AppGraph。
5. **domain 里每个类都必须能被纯单测**（`entry/src/ohosTest`，hypium）——这是第 1 条的收益，不许浪费。

## 目录地图

```
entry/src/main/ets/
├── domain/        # 纯业务：模型+规则+端口接口（Android domain/ 对应物）
│   └── model/
├── data/          # 端口实现：@kit.ArkData preferences + JSON（Android data/ 对应物）
├── platform/      # 设备能力 adapter：DeviceCertificateKit、ArkWeb 证书读取（Android platform/ 对应物）
├── app/AppGraph.ets  # 组合根：唯一装配点（Android di/AppGraph.kt 对应物）
├── ui/            # ArkUI 组件：HomeView / BrowserWeb（唯一接 ArkWeb 的地方）/ TabSwitcher / SiteEditorDialog
└── entryability/  # UIAbility 生命周期壳（保持薄，init 后转发）
```

## 与 Android 版的语义契约（移植不许漂移）

- 证书提醒：同一 host+类别 24h 最多一次（持久化，重启不重置）
- SSL 会话豁免：仅内存，进程退出失效；绝不静默放行
- 阈值：客户端证书 30 天预警、服务端 14 天
- http/https 一律应用内加载（享受 mTLS 能力），其他 scheme 交系统
- 白名单文件 `resources/rawfile/domain_whitelist.txt` 不入库（.gitignore），文件缺失=空名单=全拦
- 存储：preferences 文件 `mtls_webview`，JSON 数组 key：`sites` / `client_cert_aliases` / `cert_warn_at` / `cert_probe_at`，与 Android SharedPreferences 同名同语义

## 扩展位（MVP 故意不做，接口已预留）

- **多标签**：`domain/TabList.ets`（纯逻辑，冒烟断言见 `sh tools/domain-smoke.sh`）+ `ui/BrowserWeb.ets`（每标签一实例）+ `ui/TabSwitcher.ets`（概览层）。Web 组件常驻于 `Stack`，切换只改 `visibility`，滚动/JS/表单状态全保留。**上限 4**（ArkWeb 每标签一个渲染实例，比 Android WebView 更吃内存；改大前先实测）。
- **下载**：走**内核下载栈**（`WebDownloadManager.setDownloadDelegate` + `WebDownloadItem.start(path)`，见 `platform/KernelDownloader`）。不能用 `@ohos.request.downloadFile`：那是系统下载服务自己的网络栈，拿不到本应用选定的客户端证书、也不继承 SSL 豁免，mTLS 站点必然失败；而且它的 Promise 只代表"任务已创建"，不是下载完成。白名单与大小上限在 `onBeforeDownload` 里判，文件名规则在 `domain/FileName`。
- **文件上传**：`onShowFileSelector` → `platform/WebFilePicker`（`DocumentViewPicker`，accept 翻译规则在 `domain/AcceptTypes`；**取消也必须 `handleFileList([])`**，否则该 file input 永久挂起）。
- **全屏 FAB**：`data/SettingsStore` 通用键值可直接存 FAB 位置。
- **旁路证书探测**：`ProbeThrottle` 端口已平移；现用 ArkWeb 内建 `getCertificate()`（比 Android 的旁路连接更准——那条连接不带客户端证书，mTLS 站点必失败）。

## 与 Android 的能力差（做不到就别假装有）

- **第三方 Cookie 隔离**：Android `setAcceptThirdPartyCookies(false)` 有直接对应物；**ArkWeb SDK 无此 API**（`thirdPartyCookie` grep 为 0）。鸿蒙版无此安全边界。
- **`saveFormData=false`**：ArkWeb 无对应开关。
- **标签内存成本**：Android 8 个 WebView 尚可，ArkWeb 同规模风险更高，故上限取 4。
- **按 keyTypes/principals 过滤客户端证书**：`certificateManagerDialog.openAuthorizeDialog` 没有这两个入参，安卓 KeyChooser 的过滤能力无对应物，用户可能选到服务端不接受的证书（靠 400 清理兜底）。
- **~~SSL 错误无法定位到具体子资源~~（已解除）**：早期用 `onSslErrorEventReceive`（不带 URL）只能按当前主页 host 归因。现在改用 `onSslErrorEvent`，事件自带 `url` / `originalUrl` / `isMainFrame` / `isFatalError` / `certChainData`，主框架与子资源的证书错误可以精确区分，不再需要「主文档是否已提交」的猜测。

## 安全边界（本轮明确过的几条）

1. **白名单是主边界，但只覆盖主框架**：`onLoadIntercept`（发起时）+ `onNavigationEntryCommitted`（提交后）两道闸；后者在非白名单提交时会 `stop()` 并**把文档卸载回 about:blank**（只 stop 是假拦截——脚本早就跑了），且被拦 URL 不写回 `tab.url` / `lastUrl`。子框架/子资源与 Android 一样不受白名单约束，这是明知的边界，别当成已覆盖。
2. **危险 scheme 不外抛**：`file:` / `javascript:` / `data:` / `blob:` / `content:` / `about:` 一律 `BLOCK`；其余只放行 `mailto` / `tel` / `sms` / `geo`，未知深链 scheme 也 `BLOCK`（ArkWeb 的 `onLoadIntercept` 拿不到「是否用户手势」，页面一行 `location.href` 就能静默唤起任意能力）。**与 Android 的有意偏离**。
3. **备份能力未接入（有意）**：module.json5 里没有 `type: "backup"` 的 `extensionAbilities`，`backup_config.json` 也没有——所以系统备份根本不会带上本应用数据（这是真正的保证，不是靠配置里的 `allowToBackupRestore`）。preferences 里有书签、按站点的证书 keyUri、lastUrl，不该随云备份外流；单用户自托管工具也没有跨端恢复需求。**若将来要接备份，必须保持 `allowToBackupRestore: false` 并把 preferences 排除在外。**
4. **凭据只存引用**：客户端私钥/证书本身在系统凭据库，应用侧只存 `keyUri`，且不写 hilog（host 目前以 `%{public}s` 打印，仅本机日志，release 前应收紧）。
5. **SSL 放行永不静默，且白名单外直接 DENY**：策略三分支（PROCEED/ASK_USER/DENY）。非白名单站点的证书错误连「仍要继续」的机会都没有（`DefaultSslTrustPolicy` 依赖 `DomainWhitelist`）。会话豁免仅内存、仅该 host、仅本次运行。
6. **证书错误按帧归因，绝不静默放行**：用 `onSslErrorEvent`（自带 `url` + `isMainFrame`）。子框架/子资源 → 直接 `cancel`，不弹框、不授豁免（否则第三方端点的坏证书会给整站换来免检）；主框架 → 走 domain 三分支策略，host 取自本次出错请求的 `url`，取不到就拒绝。**不要退回 `controller.getUrl()` 或「主文档是否已提交」这套猜测**：前者在主框架 TLS 失败时返回的是上一个已提交文档，会「弹框写 A 站、实际放行 B 站」。
7. **客户端证书只发给白名单站点**：`onClientAuthenticationRequest` 的来源 host 不在白名单时直接 `ignore()`，防止白名单页面里嵌的第三方 iframe 骗取私钥使用授权。
8. **400 清理必须先有 mTLS 事实**：只有本标签确实在该 host 完成过客户端证书握手，才允许销毁用户的证书绑定；`clearClientAuthenticationCache` 不可用时提示词会如实降级。

## ArkTS 编码红线

写任何 `.ets` 前读 [arkts-redzone-rules.md](arkts-redzone-rules.md)。要点：禁 `any`/`unknown`、对象字面量必须显式类型标注、enum 无 `.name`（用 `kindLabel()`）、`JSON.parse` 结果必须 `as` 到显式接口。

状态装饰器混用（@State/@Prop/@Link/@BuilderParam）是编译能过但运行时炸的高发区（社区实测 ~41% 混用失败）：本项目只用 `@State` + `@CustomDialog` + 普通成员，新增装饰器前先想清楚单向/双向边界。

### ArkWeb 配置红线（踩过的坑，别再踩）

1. **`domStorageAccess` / `databaseAccess` 默认 `false`。** 套现成 SPA（Hermes WebUI 等）时页面能完整渲染但**所有交互失效**，控制台报 `Cannot read properties of null (reading 'getItem')`——`localStorage` 是 null。必须显式开。
2. **所有 `Web()` 属性只写在 `ui/BrowserWeb.ets`。** 多标签下若每个标签各写一套，20 个属性会立刻漂移。
3. **组件名/属性名避开内置名**：`overlay`、`visibility` 等是 ArkUI 组件属性，当自定义 prop 用会编译报 `not assignable to the same property in base type 'CustomComponent'`（已踩一次，改名 `overlayMode`）。
4. **`.onConsole` 必须挂**，把 Error/Warn 落到 hilog（TAG `ArkConsole`）。否则 ArkWeb 的 JS 报错淹没在 hilog 洪水里，页面故障完全不可观测。
5. **标签保活用 `visibility(Visibility.None)`**，不要用 `if (currentTab === id)`——后者销毁 Web 组件，页面状态全丢。

## 已知平台风险（真机验证项，别当已知工作）

- ✅ **mTLS 已真机验证**（HarmonyOS 7.0 / API 26 / 站点 `https://a.example.com:8443`）：`onClientAuthenticationRequest` → `openAuthorizeDialog` → `confirm(keyUri)` → 200。
- ✅ **HKDF 无关，但证书容器有坑**：老 Android 兼容的 `-legacy -keypbe PBE-SHA1-3DES -macalg sha1` 容器在鸿蒙装不上；用 `-keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256` 重打包即可（证书与私钥不变）。
- ⚠️ **安装入口别走「文件管理」**：卓易通（安卓容器）会抢注 `.p12` 处理器，崩出 `Exception Happen / Thread[main,5,main]`（Java 线程签名，非 ArkTS）。必须走 设置 → 证书管理 → 从存储设备安装 → **用户凭据**。
- ⚠️ **待验证**：4 个常驻 Web 的内存表现；`visibility(None)` 切回后是否掉帧/白屏。

## 移植缺口清单（对照 Android，按里程碑）

**M2 输入输出**
- 文件上传：`onShowFileSelector` → `documentViewPicker` / `photoAccessHelper`，回填 `FileSelectorResult.handleFileList()`
- 下载：`setDownloadDelegate` 处理 HTTP；`data:` / `blob:` 需 `javaScriptProxy` 桥接（与 Android `AndroidDownload` 同构）
- 文件名推断规则（title + MIME + URL 扩展名）应住 domain，Android 版写死在 `DownloadHandler.buildTitleFileName`

**M3 证书与安全补全**
- 白名单拦截页（现在拦下来是卸载回 about:blank + toast，没有专门的拦截页）
- 客户端证书过期提醒（握手时评估 chain[0]；现在只提醒服务端证书）
- （已完成）SSL 对话框同 host 去重 + DENY 分支 + host 严格化 + 子资源错误不授豁免
- （已完成）400 清理的 5s 冷却 + `clearClientAuthenticationCache()` + 「先有 mTLS 事实」前置条件
- （已完成）302/脚本跳转：非白名单提交后卸载文档回 about:blank（只 stop 是假拦截）
- （已完成）SPA pushState/hash 的 URL 同步（`onRefreshAccessedHistory`）
- （已完成）危险 scheme / 未知深链 scheme 一律 BLOCK

**M4 体验**
- 沉浸式全屏 + 可拖动浮动按钮 + 位置持久化 + 状态栏染色/图标明暗自适应
- 状态保存/恢复（进程回收、转屏）
- 书签跨端导入（Android SharedPreferences → JSON）

**不移植**
- `LegacyMigrator`（安卓内部 prefs 迁移，跨 OS 无意义）
- Material3 主题（鸿蒙走系统色）
