# ArkTS / ArkUI 编码规则（注入 AI 编程助手 System Prompt / Rules 用）

来源：华为开发者联盟官方博客《从 TypeScript 到 ArkTS：如何让 AI 写出能编译通过的鸿蒙代码》
（https://developer.huawei.com/consumer/cn/blog/topic/03224002444996399，2026-09）。
背景：ArkTS 公开语料不足 TypeScript 的 1%，大模型默认会用 TS 写法导致编译失败。
另加两条本项目补充纪律（非官方博客内容）。

---

你正在为 HarmonyOS 应用编写代码。代码语言是 ArkTS（TypeScript 的严格子集），UI 框架是 ArkUI（声明式范式）。你必须严格遵守以下所有规则，禁止使用普通 TypeScript / JavaScript 的写法。违反任何一条都可能导致编译失败。

## 一、绝对禁止（红区清单）

### 1. 类型系统
- 禁用 `any`、`unknown` 类型
- 禁用 `as any` 类型转换
- 禁用 `@ts-ignore`、`@ts-nocheck`
- 禁用结构类型（两个结构相同的类不能互相赋值，必须通过 `extends` 或 `implements` 建立关系）
- 禁止未类型标注的对象字面量
- 禁用索引访问类型 `T[K]`
- 禁用条件类型 `T extends U ? X : Y`
- 禁用 `infer` 关键字
- 禁用交叉类型 `A & B`（改用继承）
- 禁用映射类型 `[K in keyof T]`
- 禁用 `as const` 断言
- 禁用确定性赋值断言 `let v!: T`
- 禁用 `this` 类型标注
- `catch` 子句变量不得标注类型
- 禁止直接 `throw error`，必须写 `throw error as Error` 或 `throw new Error('...')`

### 2. 对象布局
- 禁止运行时动态增删对象属性（不能创建对象后临时新增未声明字段）
- 禁止动态属性访问 `obj["field"]`（例外：`Record` 类型的点语法/索引访问合法）
- 禁止索引签名 `[key: string]: T`（改用 `Array`、`Map` 或 `Record<K, V>`）
- 禁用 `Symbol()` API（除 `Symbol.iterator` 外）
- 禁用原型赋值
- 禁止对象方法重新赋值
- 禁用 `delete` 运算符（字段置 `null`/`undefined`；动态数据用 `Map.delete`）
- 禁用 `new.target`
- 禁用 JSX 表达式（使用 ArkUI 声明式 UI：`struct` + `build()`）

### 3. 运算符
- 禁用 `Function.apply`、`Function.call`、`Function.bind`
- 禁用逗号运算符（仅限 for 循环外）
- 禁用对象展开运算符（`{...obj}`）

### 4. 函数与类
- 禁止函数表达式（匿名 `function() {}`），必须使用箭头函数
- 禁止函数内声明函数（内联箭头函数表达式合法）
- 禁止生成器函数 `function*`（改用 `async/await`）
- 禁止解构赋值 / 解构变量声明 / 解构参数声明
- 禁止在 `constructor` 中声明字段（在类体中声明）
- 禁止类字段用 `#` 前缀（使用 `private` 关键字）
- 禁止构造函数类型（使用箭头函数类型别名）
- 禁止对函数声明属性（改用类的静态方法）
- 禁止在独立函数和静态方法中使用 `this`
- 禁止对象字面量初始化带方法的类或带参构造函数的类（使用 `new` 表达式）
- 禁止对象字面量用于类型声明（显式声明 `class` 或 `interface`）
- 禁止接口中的 call signature（使用 `type` 函数别名：`type I = (value: string) => void`）
- 禁止类表达式（`const C = class {}`）
- 禁止类 `implements` 类 / 接口继承类
- 禁止省略函数返回类型标注

### 5. 模块与语法
- 禁用 `var` 关键字
- 禁用 `with` 语句
- 禁用 `for...in` 遍历对象
- 禁用声明合并（类/接口/枚举）
- 禁用环境模块声明
- 禁用命名空间作为对象
- 禁用命名空间中非声明语句
- 禁用循环依赖
- 禁止 `throw` 非 Error 类型值
- 禁止 CommonJS 语法（`require`、`module.exports`）
- 禁止 `globalThis`
- 禁止副作用导入（`import 'module'`），改用动态导入 `import('module')`
- 禁止 `import type` 语法
- 禁止 `import * as` 命名空间导入（Native 模块除外）

## 二、强制要求

### 1. 类型标注
- 所有变量、函数参数、返回值必须显式标注类型
- 异步函数返回类型必须标注为 `Promise<T>`
- 对象字面量必须对应显式声明的 `class` 或 `interface`
- `JSON.parse` 返回值必须标注为 `Record<string, Object>`，先判空，再逐字段 `as` 断言
- 泛型函数调用必须显式标注类型实参

### 2. 变量声明
- 使用 `let` 声明变量，`const` 声明常量；禁止 `var`
- 禁止一行声明多个变量；优先使用 `const`

### 3. 数组类型
- 统一使用 `T[]` 表示（如 `number[]`），避免 `Array<T>`

### 4. 模块导入
- 使用 `@kit.*` 形式导入系统模块（`@ohos.*` 已废弃）
- 所有 `import` 语句必须在文件顶部
- 常见 Kit 对照：
  - `@kit.AbilityKit`（程序框架服务）
  - `@kit.ArkUI`（UI）
  - `@kit.CoreFileKit`（文件）
  - `@kit.PerformanceAnalysisKit`（日志/性能）
  - `@kit.NetworkKit`（网络）
  - `@kit.ArkData`（数据）
  - `@kit.BasicServicesKit`（基础服务，含 BusinessError）

### 5. 命名规范
- 类名、枚举名、命名空间名：UpperCamelCase
- 变量名、方法名、参数名：lowerCamelCase
- 常量名、枚举值名：全大写 + 下划线（如 `MAX_PAGE_SIZE`）
- 布尔变量加 `is`、`has`、`can`、`should` 前缀，禁止否定命名

### 6. 错误处理
- `throw` 的值必须是 `Error` 实例或 `Error` 子类实例
- `catch` / Promise 回调中 re-throw `BusinessError` 时必须写 `throw error as Error`
- 自定义异常：`class XxxError extends Error`

## 三、ArkUI 声明式 UI 规则

1. 组件结构
- `@Entry` 装饰入口组件（每个 HAP 包有且仅有一个）；`@Component` 装饰自定义组件
- 组件以 `struct` 关键字定义，`build()` 描述 UI 结构
- `build()` 有且仅有一个根容器组件（如 `Column`/`Row`）

2. 属性与事件
- 属性通过 `.` 链式调用设置
- 资源引用使用 `$r('app.type.name')` 和 `$rawfile('path')`
- 事件绑定使用箭头函数

3. 状态管理（推荐 V2）
- V2 装饰器（API 12+）：`@ComponentV2`、`@Local`（代 `@State`）、`@Param`（代 `@Prop`）、`@Event`、`@Once`、`@Monitor`（代 `@Watch`）、`@Provider`/`@Consumer`、`@ObservedV2`+`@Trace`
- **V1 与 V2 装饰器不可混用**；`@Component` 内禁 V2，`@ComponentV2` 内禁 V1

4. 生命周期
- `aboutToAppear` → `build()` → `onDidBuild` → `aboutToDisappear`
- `aboutToAppear` 禁止异步阻塞；`aboutToDisappear` 不允许改状态变量

## 四、代码风格
- 空格缩进（多数场景 2 空格），禁止 tab；行宽 ≤120；字符串单引号
- `if`/`for`/`while` 与 `(` 之间加空格，函数名与 `(` 不加
- `else`/`catch` 与 `}` 同行；二元运算符两侧空格；逗号后空格
- 大括号 `{` 与语句同行

## 五、生成代码后的自检清单
1. 用了 `any`/`unknown`/`as any`？→ 禁止
2. 动态增删对象属性？→ 禁止
3. 解构赋值？→ 禁止
4. 匿名 `function() {}`？→ 改箭头函数
5. 函数内声明函数？→ 提升顶层或内联箭头函数
6. 变量/参数/返回值全部显式标注类型？→ 必须
7. 对象字面量对应显式 interface/class？→ 必须
8. 导入用 `@kit.*`？→ 必须
9. `build()` 单根容器？→ 必须
10. V1/V2 装饰器混用？→ 禁止
11. `throw` 值是 Error 实例？→ 必须
12. 有 `var`/`for...in`/`delete`/`globalThis`？→ 禁止
13. 有 CommonJS 语法？→ 禁止
14. 异步函数返回类型 `Promise<T>` 标注？→ 必须
15. `JSON.parse` 标注类型并判空？→ 必须

---

## 本项目补充纪律（本项目的 mTLS 相关纪律，非官方清单内容）

1. **写任何 `@kit.*` API 调用前，先 grep 本地 SDK 的 `.d.ts` 确认接口名/参数/枚举值**，
   不得凭模型记忆猜 API（ArkWeb/CertificateManager 迭代快，幻觉成本高）。
2. **平台行为断言必须真机验证**：mTLS 证书链完整性、`confirm()` 路径、
   `ProxyController` 生效范围，以真机日志为准，文档与论坛说法都可能过时。
