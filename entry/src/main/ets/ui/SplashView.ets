/**
 * 应用内启动画面。
 *
 * 为什么不用系统的 `startWindowIcon`：那一张图的显示尺寸由窗口管理器决定，
 * 我们只能改图片、改不了它的显示框，实测里它比锁屏图标大出一大截，而且不同机型不一致。
 * 所以把系统那张图换成纯白（见 media/startIcon.png），首帧由我们自己画：
 * **图标尺寸/圆角/字体直接复用锁屏那套数值**，一致性由"同一个 80dp"保证，不靠目测。
 */
@Component
export struct SplashView {
  build() {
    Column() {
      Blank()

      Column() {
        Image($r('app.media.ic_app_lock'))
          .width(80)
          .height(80)
          .borderRadius(19)
          .clip(true)
          .draggable(false)
          .objectFit(ImageFit.Cover)

        Text('MT浏览器')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F1F1F')
          .margin({ top: 18 })
      }
      .alignItems(HorizontalAlign.Center)

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Center)
  }
}