import { AppGraph } from '../app/AppGraph';
import { DEFAULT_LOCK_TIMEOUT_MIN, LOCK_TIMEOUT_OPTIONS, normalizeLockTimeout } from '../domain/LockPolicy';

/**
 * 设置页（覆盖层）。只碰 AppGraph 暴露的口子：
 * 页面不直连 data/platform（check-arch R3），存的都是用户可见的两项：
 * 指纹锁开关 + 离开多久后要求解锁。
 */
@Component
export struct SettingsView {
  @State lockEnabled: boolean = false;
  @State timeoutMin: number = DEFAULT_LOCK_TIMEOUT_MIN;
  @State biometricOk: boolean = true;
  @State hint: string = '';
  onClose: () => void = (): void => {};
  /** 用户点了「立即锁定」：由页面真正上锁 */
  onLockNow: () => void = (): void => {};

  aboutToAppear(): void {
    const s = AppGraph.settings();
    this.lockEnabled = s.getLockEnabled();
    const stored = s.getLockTimeoutMinutes();
    this.timeoutMin = stored < 0 ? DEFAULT_LOCK_TIMEOUT_MIN : normalizeLockTimeout(stored);
    this.biometricOk = AppGraph.biometricAvailable();
    if (!this.biometricOk) {
      this.hint = '本机未录入指纹（或指纹被系统锁定），无法启用指纹锁';
    } else if (this.lockEnabled) {
      this.hint = '离开应用超过设定时间后，回到前台需要指纹解锁';
    }
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
      s.setLockTimeoutMinutes(this.timeoutMin);
      this.hint = '离开应用超过设定时间后，回到前台需要指纹解锁';
    } else {
      // 关掉后清时间戳，避免"关了又开"立刻被判定超时
      AppGraph.clearLockClock();
      this.hint = '';
    }
  }

  private pickTimeout(min: number): void {
    this.timeoutMin = min;
    AppGraph.settings().setLockTimeoutMinutes(min);
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
          .enabled(this.biometricOk)
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
            ForEach(LOCK_TIMEOUT_OPTIONS, (min: number) => {
              Text(min === 0 ? '立即' : `${min} 分钟`)
                .fontSize(13)
                .fontColor(this.timeoutMin === min ? Color.White : '#1F1F1F')
                .backgroundColor(this.timeoutMin === min ? '#1F1F1F' : '#F2F3F5')
                .borderRadius(8)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .onClick(() => this.pickTimeout(min))
            }, (min: number) => min.toString())
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)

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