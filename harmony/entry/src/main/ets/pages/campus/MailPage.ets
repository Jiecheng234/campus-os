import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class MailItem {
  id: string = '';
  from: string = '';
  subject: string = '';
  preview: string = '';
  date: string = '';
  isRead: boolean = false;
  hasAttachment: boolean = false;
}

function getMockMails(): MailItem[] {
  const list: MailItem[] = [];
  const m1: MailItem = new MailItem();
  m1.id = '1'; m1.from = '教务处'; m1.subject = '关于2025-2026学年选课通知';
  m1.preview = '各位同学：2025-2026学年秋季学期选课将于8月15日开始...'; m1.date = '7月25日';
  m1.isRead = false; m1.hasAttachment = true;
  list.push(m1);
  const m2: MailItem = new MailItem();
  m2.id = '2'; m2.from = '辅导员'; m2.subject = '暑期安全提示';
  m2.preview = '请各位同学注意暑期安全，离校前关闭电源门窗...'; m2.date = '7月22日';
  m2.isRead = true; m2.hasAttachment = false;
  list.push(m2);
  const m3: MailItem = new MailItem();
  m3.id = '3'; m3.from = '图书馆'; m3.subject = '图书馆暑期开放安排';
  m3.preview = '暑期期间图书馆开放时间调整为8:00-18:00...'; m3.date = '7月20日';
  m3.isRead = true; m3.hasAttachment = false;
  list.push(m3);
  const m4: MailItem = new MailItem();
  m4.id = '4'; m4.from = '课程助教'; m4.subject = '高等数学(1) 作业反馈';
  m4.preview = '同学们好，第5章作业已批改完毕，请注意查收...'; m4.date = '7月18日';
  m4.isRead = false; m4.hasAttachment = true;
  list.push(m4);
  const m5: MailItem = new MailItem();
  m5.id = '5'; m5.from = '信息中心'; m5.subject = '校园网络维护通知';
  m5.preview = '定于7月30日凌晨进行网络设备升级...'; m5.date = '7月15日';
  m5.isRead = true; m5.hasAttachment = false;
  list.push(m5);
  return list;
}

@Component
struct MailRow {
  @Prop item: MailItem = new MailItem();

  build() {
    Row() {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.item.isRead ? 'transparent' : Theme.primary)
        .border({ width: this.item.isRead ? 1 : 0, color: Theme.divider })
        .margin({ right: 12 })

      Column() {
        Row() {
          Text(this.item.from)
            .fontSize(14)
            .fontWeight(this.item.isRead ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(Theme.text)
          Blank()
          Text(this.item.date)
            .fontSize(11)
            .fontColor(Theme.textMuted)
        }
        .width('100%')

        Text(this.item.subject)
          .fontSize(14)
          .fontWeight(this.item.isRead ? FontWeight.Normal : FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')

        Row() {
          Text(this.item.preview)
            .fontSize(12)
            .fontColor(Theme.textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.item.hasAttachment) {
            Text('📎')
              .fontSize(12)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Top)
  }
}

@Component
export struct MailPage {
  onBack: () => void = () => {};
  private mails: MailItem[] = getMockMails();

  private countUnread(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.mails.length; i++) {
      if (!this.mails[i].isRead) {
        count = count + 1;
      }
    }
    return count;
  }

  @Builder
  composeButton() {
    Button('✏️')
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .fontSize(18)
      .fontColor(Theme.textInvert)
      .backgroundColor(Theme.primary)
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '校园邮件', onBack: () => { this.onBack(); }, right: this.composeButton })

      Divider().color(Theme.divider)

      // 未读计数
      Row() {
        Text(`${this.countUnread()} 封未读`)
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .padding({ left: 16, top: 8, bottom: 4 })
        Blank()
      }
      .width('100%')

      List() {
        ForEach(this.mails, (item: MailItem) => {
          ListItem() {
            MailRow({ item: item })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Theme.divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
