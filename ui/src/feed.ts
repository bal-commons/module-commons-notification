import {type AuthAdapter, LiveStream} from "@bal-commons/ui-core";
import type {Notification} from "./types.js";

export type FeedChange =
  | {type: "created"; notification: Notification}
  | {type: "read" | "unread"; id: string; readAt?: string}
  | {type: "read-all" | "reconnected"}
  | {type: "deleted"; id: string};

// One live stream per service URL, shared by every component on the page.
class NotificationFeed extends EventTarget {
  private stream?: LiveStream;
  private users = 0;

  constructor(private readonly baseUrl: string, private readonly auth?: AuthAdapter) {
    super();
  }

  subscribe(listener: (change: FeedChange) => void): () => void {
    const handler = (e: Event) => listener((e as CustomEvent<FeedChange>).detail);
    this.addEventListener("change", handler);
    if (this.users++ === 0) {
      this.stream = new LiveStream(this.baseUrl, {
        "notification.created": (notification) => this.emit({type: "created", notification}),
        "notification.read": ({id, readAt}) => this.emit({type: "read", id, readAt}),
        "notification.unread": ({id}) => this.emit({type: "unread", id}),
        "notification.read-all": () => this.emit({type: "read-all"}),
        "notification.deleted": ({id}) => this.emit({type: "deleted", id})
      }, {auth: this.auth, replay: true, onReconnect: () => this.emit({type: "reconnected"})});
      this.stream.start();
    }
    return () => {
      this.removeEventListener("change", handler);
      if (--this.users === 0) {
        this.stream?.stop();
        this.stream = undefined;
      }
    };
  }

  private emit(change: FeedChange): void {
    this.dispatchEvent(new CustomEvent("change", {detail: change}));
  }
}

const feeds = new Map<string, NotificationFeed>();

export function feedFor(baseUrl: string, auth?: AuthAdapter): NotificationFeed {
  let feed = feeds.get(baseUrl);
  if (!feed) {
    feed = new NotificationFeed(baseUrl, auth);
    feeds.set(baseUrl, feed);
  }
  return feed;
}
