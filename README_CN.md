# mtbrowser-hmos

> **鸿蒙 NEXT**（ArkTS / ArkWeb）上的轻量、以书签为中心的 mTLS 浏览器。
> 为自建在双向 TLS 后面的服务（LibreChat、管理后台、路由器控制台……）而生。
> 移植自 Android 版 [mtbrowser](https://github.com/Sail64/mtbrowser)。

## 功能

- **书签主页** —— 原生布局，增 / 改 / 删，空态引导
- **多标签** —— 每标签一个常驻 `Web`（LRU 上限 4），概览层切换 / 关闭
- **顶栏** —— 主页、地址栏（自动补 `https://`）、刷新、一键收藏、标签计数
- **悬浮全屏按钮** —— 可拖拽、记忆位置；全屏时隐藏应用栏
- **mTLS 客户端证书** —— 通过系统证书对话框按站点选择；应用侧只存凭据 `keyUri`，绝不接触私钥
- **SSL 错误可控** —— 自签 / 过期证书弹窗询问，「仍然继续」仅本次会话有效，永不静默放行
- **域名白名单** —— 只在本地的配置文件；非白名单域名在导航前拦截，**并且**在提交后再校验一次
  （`onLoadIntercept` + `onNavigationEntryCommitted`）
- **危险 scheme 拦截** —— `file:` / `javascript:` / `data:` / `blob:` / `content:` 一律不交给页面
- **下载** —— 走内核下载栈，文件名做路径穿越防护
- **文件上传** —— 支持 `<input type="file">`
- **会话持久化** —— 页面加载完成 / 切后台时把 cookie 刷盘；冷启动按**站点根**恢复标签
  （**故意不恢复深链**：未认证深链会让 LibreChat 这类服务直接清掉会话）
- **深色模式** —— 只开 `darkMode(Auto)`，**不开** `forceDarkAccess`（会把部分 SPA 打成整页纯白）

## 使用

### 1. 添加站点
在书签主页点 **＋ 添加**。浏览时点顶栏 ☆ 收藏当前页。长按书签可编辑或删除。

### 2. 标签
点标签图标打开概览：点卡片切换，✕ 关闭，**＋ 新建标签**新建。

### 3. 客户端证书（mTLS）
站点要求客户端证书时会弹出系统对话框。证书要先用
**设置 → 证书管理 → 从存储设备安装 → 用户凭据** 安装 —— **不要**从文件管理器点开 `.p12`，
安卓兼容层可能抢注处理器然后崩掉。

### 4. 白名单
把 `entry/src/main/resources/rawfile/domain_whitelist.txt.example` 复制为 `domain_whitelist.txt`，
写入允许访问的域名。`*.example.com` 匹配该域名及其子域。

## 构建

需要 DevEco Studio（或其 `devecocli`）与 **HarmonyOS SDK API 26**。

```bash
# 1. 工程配置 + 调试签名材料（不入库）
cp build-profile.example.json5 build-profile.json5
devecocli signature generate          # 在 ~/.ohos/config/ 下生成 p12/cer/p7b
#    再把四个路径与口令填进 build-profile.json5
#    （手边没设备？把 signingConfigs 整段和 products 里的 signingConfig 引用删掉，
#      构建会成功并产出 entry-default-unsigned.hap）

# 2. 本地白名单
cp entry/src/main/resources/rawfile/domain_whitelist.txt.example \
   entry/src/main/resources/rawfile/domain_whitelist.txt

# 3. 构建 / 安装
devecocli build
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b cn.tobe.mtbrowser.hmos
```

## 检查（无头，不依赖 IDE）

```bash
node tools/check-arch.mjs     # 依赖方向守卫，违规 exit 1
sh tools/domain-smoke.sh      # 115 条纯 domain 断言，在普通 Node 里跑
```

## 目录结构

```
entry/src/main/ets/
├── domain/     纯逻辑，零平台依赖（禁止 import @ohos.* / @kit.*）
├── data/       preferences 存储、仓库实现
├── platform/   ArkWeb / 证书 / 下载适配器
├── ui/         ArkUI 组件；BrowserWeb 是全项目唯一接 ArkWeb 事件的地方
├── pages/      薄控制器（Index）
└── app/        AppGraph —— 唯一组合根
```

这条边界是**机械强制**的，不靠自觉：`domain/` 必须能在普通 Node 里跑起来（冒烟测试干的正是这件事），
`ui/`、`pages/` 不得直接 import `platform/`。

## 与 Android 版的已知差距

- ArkWeb 没有第三方 cookie 隔离 API（cookie 按 host 共享，不区分端口）
- `openAuthorizeDialog` 不支持 `keyTypes` / `principals` 过滤
- `onSslErrorEventReceive` 不带出错 URL，子资源证书错误只能归到主框架
- 没有随页面背景变色的状态栏染色
- 没有书签跨端导入导出

踩过的平台坑和每个决策的理由见 [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。