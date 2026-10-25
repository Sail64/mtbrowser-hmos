import { TabMeta } from '../domain/TabList';

/**
 * 标签概览层（对应 Android ui/TabSwitcher）：半透明遮罩 + 浮动面板。
 * 只负责渲染与交互，标签数据与规则全在 domain/TabList（Index 持有）。
 */
@Component
export struct TabSwitcher {
  @Prop tabs: TabMeta[] = [];
  @Prop currentId: number = -1;
  onSelect: (id: number) => void = (): void => {};
  onClose: (id: number) => void = (): void => {};
  onCloseOthers: (id: number) => void = (): void => {};
  onNew: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩：点击空白处收起
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.onDismiss())

      Column({ space: 8 }) {
        Row() {
          Text('标签')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Text('✕')
            .fontSize(18)
            .fontColor('#999999')
            .padding(6)
            .onClick(() => this.onDismiss())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })

        List({ space: 4 }) {
          ForEach(this.tabs, (tab: TabMeta) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(tab.displayTitle())
                    .fontSize(15)
                    .fontColor('#222222')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(tab.displayUrl())
                    .fontSize(12)
                    .fontColor('#888888')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text('✕')
                  .fontSize(16)
                  .fontColor('#999999')
                  .padding({ left: 12, right: 4, top: 8, bottom: 8 })
                  .onClick(() => this.onClose(tab.id))
              }
              .width('100%')
              .padding({ left: 12, right: 4, top: 12, bottom: 12 })
              .borderRadius(10)
              .backgroundColor(tab.id === this.currentId ? '#E8F0FE' : Color.Transparent)
              .onClick(() => this.onSelect(tab.id))
              .gesture(
                LongPressGesture().onAction(() => {
                  this.onCloseOthers(tab.id);
                })
              )
            }
          }, (tab: TabMeta): string => tab.id.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 8, right: 8 })

        Button('＋ 新建标签')
          .fontSize(14)
          .fontColor('#1F1F1F')
          .backgroundColor('#F2F3F5')
          .height(38)
          .borderRadius(9)
          .margin({ left: 16, right: 16, bottom: 16, top: 4 })
          .onClick(() => this.onNew())
      }
      .width('100%')
      // 固定 55% 屏高（对齐 Android capPanelHeight）：Column 无高度时子 List 的
      // layoutWeight 无法解析，会塌成 0 高
      .height('55%')
      .backgroundColor(Color.White)
      .borderRadius({ topLeft: 18, topRight: 18 })
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
  }
}