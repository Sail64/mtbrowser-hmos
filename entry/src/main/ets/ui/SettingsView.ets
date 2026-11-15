import { AppGraph } from '../app/AppGraph';
import { DEFAULT_LOCK_TIMEOUT_MIN, normalizeLockTimeout } from '../domain/LockPolicy';

/**
 * 设置页（覆盖层）。只碰 AppGraph 暴露的口子：
 * 页面不直连 data/platform（check-arch R3），存的都是用户可见的两项：
 * 指纹锁开关 + 离开多久后要求解锁。
 */
@Component
export struct SettingsView {
  @State lockEnabled: boolean = false;
  /** 输入框里的文本（用户可能正处于编辑中间态，例如空串） */
  @State timeoutText: string = String(DEFAULT_LOCK_TIMEOUT_MIN);
  @State biometricOk: boolean = true;
  /** 回前台信号：去系统设置录完指纹回来，开关不该还是灰的 */
  @StorageLink('lock_fg_tick') @Watch('onForegroundAgain') fgTick: number = 0;
  @State hideRecents: boolean = true;
  @State hint: string = '';
  onClose: () => void = (): void => {};
  /** 用户点了「立即锁定」：由页面真正上锁 */
  onLockNow: () => void = (): void => {};

  aboutToAppear(): void {
    const s = AppGraph.settings();
    this.lockEnabled = s.getLockEnabled();
    const stored = s.getLockTimeoutMinutes();
    const min = stored < 0 ? DEFAULT_LOCK_TIMEOUT_MIN : normalizeLockTimeout(stored);
    this.timeoutText = String(min);
    this.biometricOk = AppGraph.biometricAvailable();
    this.hideRecents = s.getHideRecents();
    if (!this.biometricOk) {
      this.hint = '本机未录入指纹（或指纹被系统锁定），无法启用指纹锁';
    } else if (this.lockEnabled) {
      this.hint = '回到前台需要指纹解锁；填 0 表示一离开就锁';
    }
  }

  aboutToDisappear(): void {
    // 用户改完直接关页面（没有失焦事件）也要落盘
    this.settleTimeout();
  }

  private onForegroundAgain(): void {
    const ok = AppGraph.biometricAvailable();
    if (ok !== this.biometricOk) {
      this.biometricOk = ok;
      this.hint = ok ? '' : '本机未录入指纹（或指纹被系统锁定），无法启用指纹锁';
    }
  }

  private toggleHideRecents(on: boolean): void {
    this.hideRecents = on;
    AppGraph.settings().setHideRecents(on);
    AppGraph.applyPrivacyMode(on);
  }

  private toggleLock(on: boolean): void {
    if (on && !this.biometricOk) {
      // 没有可用指纹时绝不允许打开开关：否则用户会被自己的设置锁在门外
      this.hint = '本机未录入指纹（或指纹被系统锁定），无法启用指纹锁';
      return;
    }
    this.lockEnabled = on;
    const s = AppGraph.settings();
    s.setLockEnabled(on);
    if (on) {
      s.setLockTimeoutMinutes(this.committedTimeout());
      this.hint = '回到前台需要指纹解锁；填 0 表示一离开就锁';
    } else {
      // 关掉后清时间戳，避免"关了又开"立刻被判定超时
      AppGraph.clearLockClock();
      this.hint = '';
    }
  }

  /** 输入框文本 → 合法分钟数（空串走默认值） */
  private committedTimeout(): number {
    const raw = this.timeoutText.trim();
    if (raw === '') {
      return DEFAULT_LOCK_TIMEOUT_MIN;
    }
    return normalizeLockTimeout(Number(raw));
  }

  /** 边输边存：只存合法值，且不让空串把已存的值抹掉 */
  private onTimeoutInput(raw: string): void {
    // 只保留数字：InputType.Number 在个别输入法下仍可能带符号/空格
    let digits = '';
    for (let i = 0; i < raw.length; i++) {
      const ch = raw.charAt(i);
      if (ch >= '0' && ch <= '9') {
        digits = digits + ch;
      }
    }
    if (digits === '') {
      // 编辑中间态：只更新显示，不落盘（空串不该覆盖已存的值）
      this.timeoutText = '';
      return;
    }
    const normalized = normalizeLockTimeout(Number(digits));
    // 超过上限立刻把框里的数字纠正过来，否则「显示 9999、实际 1440」界面在撒谎
    this.timeoutText = String(normalized);
    // 不在这里落盘：逐键写会把「想输 10」的中间态 "1" 存成 1 分钟

  }

  /** 失焦/提交时把文本回写成合法值（空串 → 回到已存的值） */
  private settleTimeout(): void {
    const typed = this.timeoutText.trim();
    if (typed !== '') {
      AppGraph.settings().setLockTimeoutMinutes(normalizeLockTimeout(Number(typed)));
    }
    const stored = AppGraph.settings().getLockTimeoutMinutes();
    const min = stored < 0 ? DEFAULT_LOCK_TIMEOUT_MIN : normalizeLockTimeout(stored);
    this.timeoutText = String(min);
  }

  build() {
    Column() {
      Row() {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F1F1F')
          .layoutWeight(1)
        Text('关闭')
          .fontSize(14)
          .fontColor('#6B7280')
          .padding(8)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Divider().color('#EEEEEE')

      Row() {
        Column({ space: 3 }) {
          Text('指纹解锁')
            .fontSize(15)
            .fontColor('#1F1F1F')
          Text('锁屏后需要指纹才能继续使用')
            .fontSize(12)
            .fontColor('#8A8F98')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.lockEnabled })
          .selectedColor('#1F1F1F')
          // 指纹不可用时也不许把开关锁死：已经开着的用户必须能关掉，
          // 否则「指纹被删了 + 开关动不了」= 设置被自己的配置卡住。
          .enabled(this.biometricOk || this.lockEnabled)
          .onChange((on: boolean) => this.toggleLock(on))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (this.lockEnabled) {
        Divider().color('#EEEEEE')
        Column({ space: 10 }) {
          Text('离开后自动锁定')
            .fontSize(15)
            .fontColor('#1F1F1F')
            .width('100%')
          Row({ space: 8 }) {
            Text('离开')
              .fontSize(14)
              .fontColor('#3D3D3D')
            TextInput({ text: this.timeoutText })
              .type(InputType.Number)
              .maxLength(4)
              .width(58)
              .height(34)
              .fontSize(14)
              .fontColor('#1F1F1F')
              .textAlign(TextAlign.Center)
              .backgroundColor('#F2F3F5')
              .borderRadius(8)
              .onChange((value: string) => this.onTimeoutInput(value))
              .onSubmit(() => this.settleTimeout())
              .onBlur(() => this.settleTimeout())
            Text('分钟后自动锁定')
              .fontSize(14)
              .fontColor('#3D3D3D')
            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Button('立即锁定')
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor('#1F1F1F')
            .backgroundColor('#F2F3F5')
            .borderRadius(9)
            .margin({ top: 4 })
            .onClick(() => this.onLockNow())
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      }

      Divider().color('#EEEEEE')

      Row() {
        Column({ space: 3 }) {
          Text('隐藏任务列表预览')
            .fontSize(15)
            .fontColor('#1F1F1F')
          Text('最近任务里不显示页面内容（同窗口内也无法截屏）')
            .fontSize(12)
            .fontColor('#8A8F98')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.hideRecents })
          .selectedColor('#1F1F1F')
          .onChange((on: boolean) => this.toggleHideRecents(on))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(12)
          .fontColor(this.biometricOk ? '#8A8F98' : '#D9534F')
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 10 })
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
  }
}