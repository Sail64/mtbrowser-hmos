/**
 * 锁屏层：盖住整个应用（含网页内容），只留一个解锁入口。
 * 这里不放任何业务判断——该不该锁由 AppGraph.shouldLockNow() 决定，
 * 本组件只负责「展示 + 触发解锁」，并把结果交回页面。
 */
@Component
export struct LockScreen {
  @Prop busy: boolean = false;
  @Prop message: string = '';
  onUnlock: () => void = (): void => {};

  build() {
    Column() {
      Column({ space: 6 }) {
        // 锁形：用两个基本形状拼，不引额外图片资源
        Stack() {
          Circle()
            .width(26)
            .height(26)
            .border({ width: 3, color: '#1F1F1F' })
            .fill(Color.Transparent)
            .margin({ bottom: 12 })
          Rect()
            .width(40)
            .height(30)
            .radius(8)
            .fill('#1F1F1F')
        }
        .width(44)
        .height(46)
        .alignContent(Alignment.Bottom)

        Text('已锁定')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F1F1F')
          .margin({ top: 10 })
        Text('MT浏览器已锁定，验证指纹后继续')
          .fontSize(13)
          .fontColor('#8A8F98')
          .margin({ top: 4 })
        if (this.message !== '') {
          Text(this.message)
            .fontSize(12)
            .fontColor('#D9534F')
            .margin({ top: 8 })
        }
      }
      .alignItems(HorizontalAlign.Center)

      Button(this.busy ? '验证中…' : '用指纹解锁')
        .width('72%')
        .height(44)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor('#1F1F1F')
        .borderRadius(10)
        .enabled(!this.busy)
        .margin({ top: 28 })
        .onClick(() => this.onUnlock())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
  }
}