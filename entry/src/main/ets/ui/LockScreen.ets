/**
 * 锁屏层：盖住整个应用（含网页内容与所有覆盖层）。
 *
 * 排布：应用图标（右下角带小锁徽标）→ 应用名 → 状态行。
 * 图标放中间的理由：锁定界面第一件要说清楚的事是「哪个应用被锁了」，
 * 锁本身是通用符号，退成徽标即可。点页面任何一处都发起指纹，没有按钮。
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
        // 应用图标 + 右下角小锁徽标（白底圆 + 白描边，压在深色图形上也清晰）
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image($r('app.media.ic_app_lock'))
            .width(80)
            .height(80)
            .borderRadius(19)
            .clip(true)
            .draggable(false)
            .objectFit(ImageFit.Cover)

          Stack() {
            Image($r('app.media.ic_lock'))
              .width(14)
              .height(14)
              .draggable(false)
              .objectFit(ImageFit.Contain)
          }
          .width(26)
          .height(26)
          .backgroundColor(Color.White)
          .borderRadius(13)
          .border({ width: 2, color: Color.White })
          .shadow({ radius: 5, color: '#20000000', offsetY: 1 })
          .margin({ right: 5, bottom: 5 })
        }
        .width(80)
        .height(80)

        Text('MT浏览器')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F1F1F')
          .margin({ top: 18 })

        // 一行状态：平时「已锁定 · 轻触解锁」，认证中换成进度
        Text(this.busy ? '正在验证指纹…' : '已锁定 · 轻触解锁')
          .fontSize(13)
          .fontColor('#9AA0A6')
          .margin({ top: 7 })

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