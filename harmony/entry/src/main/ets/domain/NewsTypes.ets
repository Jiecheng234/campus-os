export class NewsEntry {
  id: string = '';
  title: string = '';
  summary: string = '';
  publishTime: string = '';
  channel: string = '';
  url: string = '';
  isNew: boolean = false;
}

export class NewsChannel {
  id: string = '';
  name: string = '';
  subscribed: boolean = false;
}
