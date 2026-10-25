import { AppGraph } from '../app/AppGraph';
import { Site } from '../domain/model/Site';
import { SaveOutcome } from '../domain/BookmarkService';
import { SiteEditorDialog } from './SiteEditorDialog';

/**
 * 书签主页（对应 Android ui/home/HomeView）：列表 + 添加/编辑/删除 + 空态引导。
 */
@Component
export struct HomeView {
  /** 父层递增触发重载（回主页时） */
  @Prop @Watch('reload') tick: number = 0;
  /** 覆盖层模式：从浏览会话进入，显示 ✕ 关闭并回到原页面 */
  @Prop overlayMode: boolean = false;
  onClose: () => void = (): void => {};
  openSite: (url: string) => void = (): void => {};
  removeSite: (site: Site) => void = (): void => {};
  @State sites: Site[] = [];
  /** dialog controller 必须存成员（局部变量会被提前释放） */
  private editorCtrl: CustomDialogController | null = null;

  reload(): void {
    this.sites = AppGraph.siteRepository().all();
  }

  aboutToAppear(): void {
    this.reload();
  }

  private save(original: Site | null, name: string, url: string): void {
    // 保存规则（规范化/去重/白名单提示）全在 domain BookmarkService，UI 只负责提示
    const result = AppGraph.bookmarks().save(original, name, url);
    const prompt = this.getUIContext().getPromptAction();
    if (result.outcome === SaveOutcome.EMPTY_URL) {
      prompt.showToast({ message: '地址不能为空' });
      return;
    }
    const base = result.outcome === SaveOutcome.SAVED && original === null ? '已添加' : '已保存';
    prompt.showToast({
      message: result.outsideWhitelist ? `${base}（该域名不在白名单，访问会被拦截）` : base
    });
    this.reload();
  }

  private showEditor(site: Site | null): void {
    const initName = site !== null ? site.name : '';
    const initUrl = site !== null ? site.url : '';
    const titleText = site !== null ? '编辑站点' : '添加站点';
    this.editorCtrl = new CustomDialogController({
      builder: SiteEditorDialog({
        titleText: titleText,
        initName: initName,
        initUrl: initUrl,
        submit: (name: string, url: string): void => this.save(site, name, url)
      }),
      autoCancel: true
    });
    this.editorCtrl.open();
  }

  build() {
    Column() {
      Row() {
        if (this.overlayMode) {
          Text('✕')
            .fontSize(20)
            .fontColor('#666666')
            .padding({ right: 10 })
            .onClick(() => this.onClose())
        }
        Text('mtbrowser')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button('＋ 添加')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor('#1F1F1F')
          .height(34)
          .borderRadius(8)
          .onClick(() => this.showEditor(null))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      if (AppGraph.whitelistIsEmpty()) {
        Text('白名单为空：所有站点都会被拦截。请检查 rawfile/domain_whitelist.txt')
          .fontSize(12)
          .fontColor('#D9534F')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.sites.length === 0) {
        Column({ space: 8 }) {
          Text('还没有书签')
            .fontSize(16)
            .fontColor('#888888')
          Text('点击右上角「＋ 添加」收藏你的 mTLS 站点')
            .fontSize(13)
            .fontColor('#AAAAAA')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.sites,
            (s: Site) => {
              ListItem() {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(s.name)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(s.url)
                      .fontSize(12)
                      .fontColor('#888888')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  // 打开站点只绑在左侧信息区：绑到整行会和右边「⋯」的菜单抢点击
                  .onClick(() => this.openSite(s.url))

                  Button('⋯', { type: ButtonType.Circle })
                    .fontSize(16)
                    .fontColor('#5F6368')
                    .backgroundColor('#F2F3F5')
                    .width(30)
                    .height(30)
                    .bindMenu([
                      { value: '编辑', action: (): void => this.showEditor(s) },
                      { value: '删除', action: (): void => this.removeSite(s) }
                    ])
                }
                .width('100%')
                .padding(14)
                .backgroundColor(Color.White)
                .borderRadius(12)
              }
            },
            (s: Site): string => `${s.id}-${s.name}-${s.url}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
