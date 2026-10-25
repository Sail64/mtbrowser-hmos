/**
 * 站点编辑对话框（对应 Android ui/home/SiteEditorDialog）：名称 + 地址。
 */
@CustomDialog
export struct SiteEditorDialog {
  controller: CustomDialogController;
  titleText: string = '添加站点';
  initName: string = '';
  initUrl: string = '';
  submit: (name: string, url: string) => void = (): void => {};
  @State name: string = '';
  @State url: string = '';

  aboutToAppear(): void {
    this.name = this.initName;
    this.url = this.initUrl;
  }

  build() {
    Column({ space: 12 }) {
      Text(this.titleText)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
      TextInput({ text: this.name, placeholder: '名称（可留空，自动用域名）' })
        .fontSize(14)
        .onChange((v: string) => {
          this.name = v;
        })
      TextInput({ text: this.url, placeholder: 'https://…' })
        .fontSize(14)
        .onChange((v: string) => {
          this.url = v;
        })
      Row({ space: 16 }) {
        Button('取消')
          .fontColor('#1F1F1F')
          .backgroundColor('#F2F3F5')
          .height(40)
          .borderRadius(9)
          .layoutWeight(1)
          .onClick(() => this.controller.close())
        Button('保存')
          .fontColor(Color.White)
          .backgroundColor('#1F1F1F')
          .height(40)
          .borderRadius(9)
          .layoutWeight(1)
          .onClick(() => {
            // 校验归 domain（BookmarkService 的 SaveOutcome.EMPTY_URL），这里不再重复一份文案
            this.submit(this.name, this.url);
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(20)
    .width('90%')
  }
}
