import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class NewsItem {
  id: string = '';
  title: string = '';
  summary: string = '';
  publishTime: string = '';
  channel: string = '';
  isNew: boolean = false;
}

function getMockNews(): NewsItem[] {
  const list: NewsItem[] = [];
  const n1: NewsItem = new NewsItem();
  n1.id = '1'; n1.title = '清华大学2025届本科生毕业典礼举行'; n1.channel = '头条';
  n1.summary = '7月6日上午，清华大学2025届本科生毕业典礼在东大操场举行。'; n1.publishTime = '7月6日'; n1.isNew = true;
  list.push(n1);
  const n2: NewsItem = new NewsItem();
  n2.id = '2'; n2.title = '关于2025-2026学年秋季学期选课的通知'; n2.channel = '教务';
  n2.summary = '2025-2026学年秋季学期选课将于8月15日9:00正式开始。'; n2.publishTime = '7月15日';
  list.push(n2);
  const n3: NewsItem = new NewsItem();
  n3.id = '3'; n3.title = '图书馆暑期开放时间安排'; n3.channel = '校园服务';
  n3.summary = '暑期期间各图书馆开放时间调整为8:00-18:00。'; n3.publishTime = '7月1日';
  list.push(n3);
  const n4: NewsItem = new NewsItem();
  n4.id = '4'; n4.title = '校园一卡通升级通知'; n4.channel = '信息化';
  n4.summary = '校园一卡通系统将于本周末进行升级维护。'; n4.publishTime = '7月20日';
  list.push(n4);
  const n5: NewsItem = new NewsItem();
  n5.id = '5'; n5.title = '暑期社会实践出征仪式举行'; n5.channel = '学生活动';
  n5.summary = '2025年暑期社会实践出征仪式近日在蒙民伟音乐厅举行。'; n5.publishTime = '7月18日';
  list.push(n5);
  return list;
}

@Component
export struct NewsPage {
  onBack: () => void = () => {};
  private news: NewsItem[] = getMockNews();

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '校园新闻', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      List() {
        ForEach(this.news, (item: NewsItem) => {
          ListItem() {
            Column() {
              Row() {
                if (item.isNew) {
                  Text('NEW')
                    .fontSize(10)
                    .fontColor(Theme.warning)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor('rgba(217,119,6,0.10)')
                    .margin({ right: 6 })
                }
                Text(item.channel)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor(Theme.surfaceAlt)
              }
              .width('100%')
              .margin({ bottom: 6 })

              Text(item.title)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ bottom: 6 })

              Row() {
                Text(item.summary)
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(item.publishTime)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 12 })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .alignItems(HorizontalAlign.Start)
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
