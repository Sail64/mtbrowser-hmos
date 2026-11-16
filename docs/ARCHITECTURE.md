# mtbrowser-hmos 架构说明

> 本文件原计划放 AGENTS.md（自动被编码 agent 加载），因该文件名受写保护需逐项批准，改放此处。
> **依赖方向由 `tools/check-arch.mjs` 机械强制，违规 exit 1。**

Android 版 `code/mtbrowser` 的 HarmonyOS NEXT 移植。

**真机验证过（HarmonyOS 7.0 / API 26）**：书签主页增删、单标签浏览、mTLS 客户端证书握手（自建 mTLS 站点实测 200）、SSL 错误弹窗放行、服务端证书过期提醒、域名白名单拦截、SPA 站点（pushState 路由）正常交互。

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

1. **白名单是主边界，但只覆盖主框架，且不拦内网地址**：`onLoadIntercept`（发起时）+ `onNavigationEntryCommitted`（提交后）两道闸；后者在非白名单提交时会 `stop()` 并**把文档卸载回 about:blank**（只 stop 是假拦截——脚本早就跑了）。被拦 URL 会写回 `tab.url` 并弹拦截卡片，**URL 可选中复制、也有「复制链接」按钮**——拦了又抄不走是死局，用户连「自己被拦的是什么地址」都拿不到。
   **内网/本机地址一律放行**（`domain/LocalNetwork`）：IPv4 私有段 10/8、172.16/12、192.168/16、回环 127/8、链路本地 169.254/16，IPv6 回环与 ULA/链路本地，`localhost`、`*.local`、以及不含点的单标签主机名（`nas`、`router`）。理由：白名单用来挡公网误入，内网可达性由所在网络决定，浏览器白名单不是网络边界；要求把 NAS/路由器地址抄进名单只会制造"忘了加就整站不可用"的假故障。**公网域名与公网 IP 仍然必须命中名单。**
   子框架/子资源与 Android 一样不受白名单约束，这是明知的边界，别当成已覆盖。
   **两条拦截路径对界面状态的影响不同，别当成一条**：`onNavigationEntryCommitted` 是「提交后拦截」，文档已被卸成 `about:blank`，地址栏显示这条失败地址（等同浏览器错误页）；`onLoadIntercept` 是「发起时拦截」，当前页面还停着，**地址栏绝不能改写**，被拦地址只在拦截卡片里给出。卡片状态由 `domain/BlockedCards` 统一管理，**两个状态必须分开**：`cards`（tabId→被拦 URL，只管界面卡片）与 `unloaded`（文档确实已被卸载）。落盘只取 `persistedUrlOf()`——只有 `unloaded` 的标签存空串，**活页面必须原样保留自己的 URL**（曾经把两者混成一个 Map，导致「点一个白名单外链接，正在看的那个页面被持久化成空串」）。六个入口 `block / dismiss / navigate / pageEnd / forget / cardUrlOf` 缺一不可：`dismiss`（「知道了」/返回键）少一行，卡片就会在切标签回来后复活。
   **已知副作用（有意接受）**：内网放行后，任何已放行的公网页面都能用顶层导航把浏览器带到内网设备（`location='http://192.168.0.1/…'`，CSRF 面变大）。以前这些地址被白名单挡住。要收紧就得给内网导航加「必须可归因为用户操作」的一次性令牌，目前没做。
2. **危险 scheme 不外抛**：`file:` / `javascript:` / `data:` / `blob:` / `content:` / `about:` 一律 `BLOCK`；其余只放行 `mailto` / `tel` / `sms` / `geo`，未知深链 scheme 也 `BLOCK`。**与 Android 的有意偏离**。补充事实：`onLoadIntercept` 的 `WebResourceRequest` **确实**带 `isRequestGesture()`（见第 9 条），但外部 scheme 这条策略刻意不对它做区分——放行与否是「这个 scheme 会不会造成副作用外溢」的问题，不是「谁触发的」的问题。
3. **备份能力未接入（有意）**：module.json5 里没有 `type: "backup"` 的 `extensionAbilities`，`backup_config.json` 也没有——所以系统备份根本不会带上本应用数据（这是真正的保证，不是靠配置里的 `allowToBackupRestore`）。preferences 里有书签、按站点的证书 keyUri、lastUrl，不该随云备份外流；单用户自托管工具也没有跨端恢复需求。**若将来要接备份，必须保持 `allowToBackupRestore: false` 并把 preferences 排除在外。**
4. **凭据只存引用**：客户端私钥/证书本身在系统凭据库，应用侧只存 `keyUri`，且不写 hilog（host 目前以 `%{public}s` 打印，仅本机日志，release 前应收紧）。
5. **SSL 放行永不静默，且白名单外直接 DENY**：策略三分支（PROCEED/ASK_USER/DENY）。非白名单站点的证书错误连「仍要继续」的机会都没有（`DefaultSslTrustPolicy` 依赖 `DomainWhitelist`）。会话豁免仅内存、仅该 host、仅本次运行。
6. **证书错误按帧归因，绝不静默放行**：用 `onSslErrorEvent`（自带 `url` + `isMainFrame`）。子框架/子资源 → 直接 `cancel`，不弹框、不授豁免（否则第三方端点的坏证书会给整站换来免检）；主框架 → 走 domain 三分支策略，host 取自本次出错请求的 `url`，取不到就拒绝。**不要退回 `controller.getUrl()` 或「主文档是否已提交」这套猜测**：前者在主框架 TLS 失败时返回的是上一个已提交文档，会「弹框写 A 站、实际放行 B 站」。
7. **客户端证书只发给白名单站点**：`onClientAuthenticationRequest` 的来源 host 不在白名单时直接 `ignore()`，防止白名单页面里嵌的第三方 iframe 骗取私钥使用授权。
8. **400 清理必须先有 mTLS 事实**：只有本标签确实在该 host 完成过客户端证书握手，才允许销毁用户的证书绑定；`clearClientAuthenticationCache` 不可用时提示词会如实降级。

9. **链接点击另开标签，判定只用 ArkWeb 给的请求事实**：`onLoadIntercept` 的判定顺序由 `domain/InterceptDecision.decideIntercept` 统一（scheme 闸门 → **白名单** → 裂标签 → 放行），顺序本身有断言守着；`domain/LinkOpenPolicy.shouldOpenInNewTab` 要求同时满足「主框架 + `isRequestGesture()` 为真 + 非 `isRedirect()` + GET + http(s) + 目标与当前页去掉 `#hash` 后不同」。少一条就留在原标签：否则 302/OAuth 回跳会裂出多个标签、POST 表单换标签会丢提交上下文、SPA 自动跳转会把标签刷满。
   **已知策略上限（不是 bug）**：ArkWeb 的 `WebResourceRequest` 无法区分「点链接」与「GET 表单提交」，所以站内搜索框/筛选表单回车也会裂标签。要撤销只能做成设置开关，目前默认开。
   **被白名单拦住的链接不裂标签**（先拦后判），避免「新标签 + 另一张拦截卡片」两个坑。**已有同 URL 标签时直接切过去**（连点/双击不重复建，也兜住内核重复回调）；**标签已满（`DEFAULT_MAX_TABS=4`）时覆盖当前标签而不是 LRU 淘汰**——被淘汰的可能是正在填表/上传/下载的那一个，且淘汰无任何提示。
   `target=_blank` / `window.open` 靠 `BrowserWeb` 里显式 `.multiWindowAccess(false)` 落回同一条主框架导航路径（不再依赖默认值）；因此不需要 `onWindowNew`/`setWebController` 那套多窗口机制。新标签复用 `openUrl(url, reuseCurrent=false)`，且**从内核同步回调里推迟一拍**（`setTimeout 0`）再建组件，避免在回调栈内重建 UI。

## 指纹锁 / 自动锁定

- **超时时长由用户手填**（`离开 [__] 分钟后自动锁定`，默认 5）：`normalizeLockTimeout` 负责收敛——非有限数/负数回落默认 5、超过一天收敛到 1440、小数截断。**不要**改回固定档位（1/5/15/30），用户要的是任意值。
- **分层**：`domain/LockPolicy`（纯函数：离开多久算超时、脏数据收敛、文案）→ `data/SettingsStore`（三个键：`lock_enabled` / `lock_timeout_min` / `lock_last_bg_at`）→ `platform/BiometricAuth`（`userAuth.getUserAuthInstance` 的一次性实例封装）→ `app/AppGraph`（`shouldLockNow` / `authenticateBiometric` / `noteAppBackground` / `clearLockClock`）→ `ui/LockScreen` 与 `ui/SettingsView`。UI 不直连 platform（check-arch R3）。
- **三条硬规则**（都是"别把用户锁在门外"）：
  1. `getAvailableStatus()` 抛异常 = 不可用。**指纹不可用时一律不上锁**，而不是锁住解不开。
  2. 系统时间被回拨（`now < lastBackgroundAt`）**判为超时**（fail-closed）：宁可多要一次指纹。
  3. 冷启动（进程被杀）**等价于离开很久** → 开了锁就必须先解锁。
- **UserAuthInstance 是一次性的**：每次解锁都要重新 `getUserAuthInstance()`；复用同一实例第二次 `start()` 不会回调，锁屏会永远解不开。`skipLockedBiometricAuth: true` 让系统锁定态直接失败返回，而不是弹一个过不去的框。
- **前台信号走 AppStorage，不直接操作 UI**：`EntryAbility.onForeground` 只把 `lock_fg_tick` +1，页面用 `@StorageLink + @Watch` 收到后再问 `AppGraph.shouldLockNow()`。Ability 不持有页面引用，页面也不轮询。
- **锁屏态吞掉返回键**（返回键不能成为绕过指纹的通道）；要离开应用请用系统 Home。
- **锁屏期间不产生任何 mTLS 握手**：`InterceptAction.SUSPEND_FOR_LOCK` 在 domain 里，排在 scheme 与白名单之前（锁屏时连 `mailto:` 都不该拉起别的应用），只有 `about:blank` 放行。首次导航由 `tryLoadPending` 早退推迟，解锁时 `@Watch('onLockStateChanged')` 补发；被丢弃的 GET 跳转解锁后重放一次（POST 不重放，避免重复提交）。**教训**：只挡主框架不够——若不推迟首次导航，握手会发生在锁屏后面，客户端证书被挡掉 → 服务端 400（真机上就是这么炸的）。
- **锁屏期间仍使用「已缓存、已授权」的客户端身份**：它不弹 UI、不泄露信息，却是 mTLS 站点后台轮询的命脉；把这条也挡掉会让所有 XHR 401、甚至掉登录。只有**需要弹选择器**的路径才被压制，并记下来解锁后自动重载一次。
- **冷启动不许露一帧网页**：两道闸。①锁状态在 `onWindowStageCreate` 里、`loadContent` **之前**写进 `lock_state`，`Index.locked` 的初值直接读它（不能"先 false 再在 aboutToAppear 改 true"，那是一帧内容）；②桌面图标启动时的"恢复动效"用的是系统在切走那一刻取的那一帧，`onBackground` 再盖就晚了，所以订阅 `windowStageEvent`：`INACTIVE/HIDDEN` → `app_cover=true` 立刻盖成启动页样式，`ACTIVE` → 延迟 120ms 撤（避免指纹框/文件选择器这类系统弹框回焦时闪白）。隐私模式挡的是任务列表缩略图，挡不住这条动效，两者必须分开处理。
- **页面媒体不进系统播控**：`.enableWebAVSession(false)`。默认开启时，页面一播放音视频系统就会在通知栏/播控中心挂一张媒体卡，卡上带页面标题、卡上的播放暂停切歌可被未解锁的人操作。点击卡片本身绕不过锁（`launchType: singleton` → `onNewWant` + `onForeground` → 同一条 `shouldLockNow()` 判定），但泄漏标题与操作面，故整体关闭。代价：失去系统级播控，声音照旧但没法从通知栏暂停。
- **任务列表预览 / 截屏**：走窗口隐私模式 `setWindowPrivacyMode(true)`，需要 `ohos.permission.PRIVACY_WINDOW`（`normal` / `system_grant`，已声明并实测授予）。注意它是**整窗口常开**：最近任务的缩略图是系统在切换动画那一刻取的，`onBackground` 回来时图已生成，那时候再开只能挡下一次。代价是同窗口内用户也截不了图，所以做成设置项 `hide_recents`（默认开）。只能经 `AppGraph.applyPrivacyMode()` 下发，避免 UI 与 Ability 各拿一个 window 实例互相覆盖。
- **启动页不用系统图标**：`startWindowIcon` 的显示尺寸由窗口管理器决定（只能换图、改不了它的框，实测比锁屏图标大很多且随机型变化）。所以 `media/startIcon.png` 换成 8×8 纯白，首帧由 `ui/SplashView` 自己画，**图标 80dp / 圆角 19 / 字体 17 Medium 与锁屏完全同源**；最短展示 500ms、兜底 1500ms、首屏 `onPageEnd` 即关。锁屏已经在盖着时不画启动页（避免叠加）。
- **全局锁状态通道**：`Index.setLocked()` 是 `AppStorage['lock_state']` 的**唯一**写入口（页面用 `@StorageProp` 单向读取，写不回去），同时同步给 `AppGraph.setUiLocked()` 供 platform 层（下载）询问。锁屏期间：SSL 告警/证书选择器/文件选择器/下载全部不产生副作用；SSL 对话框的 `.then` 还要复核一次锁状态，防止「框在锁屏前打开、锁屏后被点」。
- **返回链顺序**（`onBackPress`）：锁屏 → 设置页 → 全屏 → 拦截卡片 → 标签概览 → 主页覆盖层 → 网页后退 → 回主页。新增覆盖层必须同时接进这条链，否则返回键会穿透到底下的网页后退（设置页就漏过一次）。
- **这不是加密**：它只是盖在 UI 上的一道闸。preferences 里的站点/书签、Web 内核里的页面内存、以及任务切换器里的最近任务缩略图都**没有**被加密或遮蔽。要用系统级隐私（禁止截屏/遮蔽最近任务）需要额外接 `setWindowPrivacyMode`，目前**没接**，别在 README 里宣称"数据已加密"。

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

- ✅ **mTLS 已真机验证**（HarmonyOS 7.0 / API 26 / 站点 `https://mtsite.example.com`）：`onClientAuthenticationRequest` → `openAuthorizeDialog` → `confirm(keyUri)` → 200。
- ✅ **HKDF 无关，但证书容器有坑**：老 Android 兼容的 `-legacy -keypbe PBE-SHA1-3DES -macalg sha1` 容器在鸿蒙装不上；用 `-keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256` 重打包即可（证书与私钥不变）。
- ⚠️ **安装入口别走「文件管理」**：卓易通（安卓容器）会抢注 `.p12` 处理器，崩出 `Exception Happen / Thread[main,5,main]`（Java 线程签名，非 ArkTS）。必须走 设置 → 证书管理 → 从存储设备安装 → **用户凭据**。
- ⚠️ **`visibility(Visibility.None)` 切回后必须延迟再导航**（实测结论，非待验证项）：后台标签的 Web 组件从隐藏变可见的**同一帧**发 `loadUrl`，内核会立刻 `ERR_ABORTED(-3)` 掐掉这次导航，页面永远停在 `about:blank`；而地址栏显示的是 `tab.url`（真的），表现为「地址栏有 URL、怎么刷新都白」。正确做法是首次导航由 Web 组件自己监听"变为可见"后延迟 ~250ms 补发，父层不要隔空点隐藏标签的 controller。
- ⚠️ **待验证**：4 个常驻 Web 的内存表现。

## 应用名 / 图标（改了一定要 bump versionCode）

应用名在配置里有**两个来源，必须同时改、且保持一致**，否则不同系统界面会显示不同名字：

| 配置 | 资源 | 影响哪里 |
|---|---|---|
| `AppScope/app.json5` → `app.label` | `AppScope/.../string.json` → `app_name` | **系统级**：设置 → 应用和服务列表、权限弹窗、通知抬头、以及鸿蒙 7 状态栏左上角「快捷返回前应用」 |
| `entry/src/main/module.json5` → `abilities[].label` | `entry/.../string.json` → `EntryAbility_label` | **桌面图标名**（入口 Ability 的 label 优先级高于 `app.label`） |

> DevEco 新建工程的默认值是 `app_name = "mtbrowser"`、`EntryAbility_label = "label"`，
> 不改就直接上真机，桌面和状态栏都会显示 `label`——本工程踩过这个坑。
> 另外 `module_desc` / `EntryAbility_desc` 也是模板占位（`module description` / `description`）。

**改完必须 `versionCode + 1` 再装**：应用名和图标都属于安装信息，被 launcher / bundle manager 缓存，
覆盖安装同样的 versionCode 不会刷新（本项目换图标、改名各踩过一次）。稳妥做法是 `hdc uninstall` 后重装。
本工程没有 `en_US` / `zh_CN` 资源目录，只有 `base`；将来要做多语言，这几个 string 要在每个限定目录里各写一份。

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
