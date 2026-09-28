import {type AuthAdapter, request} from "@bal-commons/ui-core";
import type {Box, ListOptions, Notification, NotificationPage, UnreadCount} from "./types.js";

// Typed calls to the notification service, as the signed-in user.
export class NotificationClient {
  constructor(readonly baseUrl: string, private readonly auth?: AuthAdapter) {}

  list(options: ListOptions = {}): Promise<NotificationPage> {
    return request(this.baseUrl, "/notifications", {auth: this.auth, query: {...options}});
  }

  unreadCount(): Promise<UnreadCount> {
    return request(this.baseUrl, "/notifications/unread-count", {auth: this.auth});
  }

  markRead(id: string): Promise<Notification> {
    return request(this.baseUrl, `/notifications/${encodeURIComponent(id)}/read`, {method: "PUT", auth: this.auth});
  }

  markUnread(id: string): Promise<Notification> {
    return request(this.baseUrl, `/notifications/${encodeURIComponent(id)}/read`, {method: "DELETE", auth: this.auth});
  }

  markAllRead(filter: {box?: Box; role?: string; category?: string; correlationId?: string} = {}): Promise<{count: number}> {
    return request(this.baseUrl, "/notifications/read-all", {method: "POST", body: filter, auth: this.auth});
  }
}
