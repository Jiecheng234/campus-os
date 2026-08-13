import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class Device {
  mac: string = '';
  ip: string = '';
  name: string = '';
  online: boolean = false;
}

class NetworkInfo {
  account: string = '';
  balance: number = 0;
  usage: number = 0;
  totalQuota: number = 0;
  devices: Device[] = [];
}

function getMockNetwork(): NetworkInfo {
  const info: NetworkInfo = new NetworkInfo();
  info.account = 'wangj23';
  info.balance = 15.80;
  info.usage = 42.5;
  info.totalQuota = 100;
  const d1: Device = new Device();
  d1.mac = 'AA:BB:CC:DD:EE:01'; d1.ip = '10.10.1.23'; d1.name = 'HUAWEI Mate 80'; d1.online = true;
  info.devices.push(d1);
  const d2: Device = new Device();
  d2.mac = 'AA:BB:CC:DD:EE:02'; d2.ip = '10.10.1.45'; d2.name = 'MacBook Pro'; d2.online = false;
  info.devices.push(d2);
  const d3: Device = new Device();
  d3.mac = 'AA:BB:CC:DD:EE:03'; d3.ip = '10.10.1.67'; d3.name = 'iPad'; d3.online = false;
  info.devices.push(d3);
  return info;
}

@Component
export struct NetworkPage {
  onBack: () => void = () => {};
  private network: NetworkInfo = getMockNetwork();

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '校园网络', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 账户信息卡片
          Column() {
            Text('账户余额')
              .fontSize(13)
              .fontColor(Theme.textMuted)
            Text(`¥${this.network.balance.toFixed(2)}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.primary)
              .margin({ top: 4 })

            // 用量进度条
            Row() {
              Text('已用流量')
                .fontSize(12)
                .fontColor(Theme.textMuted)
              Blank()
              Text(`${this.network.usage}G / ${this.network.totalQuota}G`)
                .fontSize(12)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
            .margin({ top: 12, bottom: 4 })

            Row() {
              Row()
                .width(Math.floor(this.network.usage / this.network.totalQuota * 100) + '%')
                .height(6)
                .borderRadius(3)
                .backgroundColor(Theme.primary)
            }
            .width('100%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(Theme.surfaceAlt)

            Button('充值')
              .type(ButtonType.Capsule)
              .fontSize(13)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .margin({ top: 14 })
          }
          .width('100%')
          .padding(20)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })
          .alignItems(HorizontalAlign.Center)

          // 在线设备
          Column() {
            Text('在线设备 (' + String(this.network.devices.length) + ')')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.network.devices, (device: Device, index: number) => {
              Row() {
                Column() {
                  Row() {
                    Row()
                      .width(8)
                      .height(8)
                      .borderRadius(4)
                      .backgroundColor(device.online ? Theme.success : Theme.textMuted)
                      .margin({ right: 8 })
                    Text(device.name)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.text)
                    Text(device.online ? ' 在线' : ' 离线')
                      .fontSize(11)
                      .fontColor(device.online ? Theme.success : Theme.textMuted)
                  }
                  Text('IP: ' + device.ip + '  MAC: ' + device.mac)
                    .fontSize(11)
                    .fontColor(Theme.textMuted)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (device.online) {
                  Button('注销')
                    .type(ButtonType.Capsule)
                    .fontSize(11)
                    .fontColor(Theme.error)
                    .backgroundColor('rgba(220,38,38,0.08)')
                }
              }
              .width('100%')

              if (index < this.network.devices.length - 1) {
                Divider().color(Theme.divider).margin({ top: 10, bottom: 10 })
              }
            })
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })

          Blank().height(32)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
