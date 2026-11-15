/**
 * 锁屏层：盖住整个应用（含网页内容与所有覆盖层）。
 *
 * 交互刻意做成「点页面任何一处就发起指纹」——没有大按钮：
 * 大按钮既占视觉重量，又暗示「必须点这里」；真实场景是掏出手机就想直接把手指放上去。
 * 该不该锁由 AppGraph.shouldLockNow() 决定，本组件只负责展示与发起解锁。
 */
@Component
export struct LockScreen {
  @Prop busy: boolean = false;
  @Prop message: string = '';
  onUnlock: () => void = (): void => {};

  build() {
    Column() {
      Blank()

      Column() {
        Image($r('app.media.ic_lock'))
          .width(42)
          .height(42)
          .draggable(false)
          .objectFit(ImageFit.Contain)

        Text('已锁定')
          .fontSize(19)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F1F1F')
          .margin({ top: 20 })

        // 只留一行小字：验证中换成状态，其余时候就是「轻触解锁」
        Text(this.busy ? '正在验证指纹…' : '轻触解锁')
          .fontSize(13)
          .fontColor('#9AA0A6')
          .margin({ top: 8 })

        if (this.message !== '') {
          Text(this.message)
            .fontSize(12)
            .fontColor('#D9534F')
            .margin({ top: 14 })
            .width('80%')
            .textAlign(TextAlign.Center)
        }
      }
      .alignItems(HorizontalAlign.Center)

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Center)
    // 整屏可点；busy 期间重复点击由页面侧闸门挡住，不会连开多个认证框
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => this.onUnlock())
  }
}