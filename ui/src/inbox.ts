import {type AuthAdapter, relativeTime, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement, nothing} from "lit";
import {NotificationClient} from "./client.js";
import {type FeedChange, feedFor} from "./feed.js";
import type {Box, ListOptions, Notification, Severity} from "./types.js";

const BOXES: {box: Box; label: string}[] = [
  {box: "all", label: "All"}, {box: "personal", label: "Personal"}, {box: "role", label: "Roles"}
];

/**
 * The caller's personal and role notifications, live, with read state.
 * @fires commons-notification-click - A notification was clicked; `detail.notification`. Cancelable: by default it
 * is marked read.
 * @csspart header - The tabs and "Mark all read".
 * @csspart list - The notification list.
 * @csspart item - One notification.
 * @csspart mark-all - The "Mark all read" button.
 * @csspart filters - The unread and severity filters (with `show-filters`).
 * @csspart empty - The empty state.
 * @slot empty - Replaces the "No notifications." text.
 */
export class CommonsInbox extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    auth: {attribute: false},
    box: {type: String, reflect: true},
    pageSize: {type: Number, attribute: "page-size"},
    hideTabs: {type: Boolean, attribute: "hide-tabs"},
    unreadOnly: {type: Boolean, attribute: "unread-only", reflect: true},
    severity: {type: String},
    correlationId: {type: String, attribute: "correlation-id"},
    showFilters: {type: Boolean, attribute: "show-filters"},
    items: {state: true, attribute: false},
    nextCursor: {state: true, attribute: false},
    loading: {state: true, attribute: false},
    error: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare auth?: AuthAdapter;
  declare box: Box;
  declare pageSize: number;
  declare hideTabs: boolean;
  /** Shows only unread notifications. */
  declare unreadOnly: boolean;
  /** Shows only this severity: `INFO`, `WARNING`, `ERROR` or `SUCCESS`. */
  declare severity?: Severity;
  /** Shows only the notifications about this business object, e.g. an order or case ID. */
  declare correlationId?: string;
  /** Shows the unread and severity filters in the header. */
  declare showFilters: boolean;
  /** @internal */
  declare items: Notification[];
  /** @internal */
  declare nextCursor?: string;
  /** @internal */
  declare loading: boolean;
  /** @internal */
  declare error?: string;
  private unsubscribe?: () => void;

  constructor() {
    super();
    this.baseUrl = "";
    this.box = "all";
    this.pageSize = 20;
    this.hideTabs = false;
    this.unreadOnly = false;
    this.showFilters = false;
    this.items = [];
    this.loading = false;
  }

  static override styles = [tokens, css`
    :host { display: block; background: var(--_bg); border: 1px solid var(--_border); border-radius: var(--_radius); }
    header { display: flex; gap: 4px; align-items: center; padding: 8px; border-bottom: 1px solid var(--_border); }
    .tab, .link, .more {
      font: inherit; font-size: 12px; border: 1px solid transparent; border-radius: 6px; padding: 4px 10px;
      background: none; color: var(--_fg); cursor: pointer;
    }
    .tab[aria-selected="true"] { background: var(--_accent-soft); border-color: var(--_accent); }
    .link { margin-left: auto; color: var(--_accent); }
    .tabs { display: flex; gap: 4px; }
    .filters { display: flex; gap: 8px; align-items: center; font-size: 12px; color: var(--_muted); }
    .filters select { font: inherit; font-size: 12px; background: var(--_bg); color: var(--_fg);
      border: 1px solid var(--_border); border-radius: 6px; padding: 2px 4px; }
    button:focus-visible { outline: 2px solid var(--_accent); outline-offset: 1px; }
    ul { list-style: none; margin: 0; padding: 4px; display: grid; gap: 4px; }
    li {
      display: grid; grid-template-columns: 1fr auto; gap: 2px 8px; padding: 8px 10px; border-radius: 6px;
      border-left: 3px solid var(--_info); cursor: pointer;
    }
    li:hover { background: var(--_surface); }
    li.WARNING { border-left-color: var(--_warning); } li.ERROR { border-left-color: var(--_error); }
    li.SUCCESS { border-left-color: var(--_success); }
    li.read { opacity: .6; }
    .title { font-weight: 600; font-size: 14px; }
    .unread-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--_accent); align-self: center; }
    .body { grid-column: 1 / -1; font-size: 13px; }
    .meta { grid-column: 1 / -1; font-size: 11px; color: var(--_muted); display: flex; gap: 8px; }
    .toggle { border: none; background: none; color: var(--_accent); cursor: pointer; font: inherit; padding: 0; }
    .empty, .error { padding: 16px; font-size: 13px; color: var(--_muted); text-align: center; }
    .error { color: var(--_error); }
    .more { display: block; margin: 4px auto 8px; border-color: var(--_border); }
  `];

  override connectedCallback(): void {
    super.connectedCallback();
    if (this.baseUrl) {
      this.start();
    }
  }

  override disconnectedCallback(): void {
    super.disconnectedCallback();
    this.unsubscribe?.();
  }

  override updated(changed: Map<string, unknown>): void {
    const filters = ["box", "unreadOnly", "severity", "correlationId"].some((name) => changed.has(name));
    if ((changed.has("baseUrl") || filters) && this.baseUrl && this.isConnected) {
      if (changed.has("baseUrl")) {
        this.start();
      } else {
        void this.reload();
      }
    }
  }

  // Refetches the first page.
  async reload(): Promise<void> {
    this.loading = true;
    try {
      const page = await this.client().list({...this.query(), limit: this.pageSize});
      this.items = page.items;
      this.nextCursor = page.nextCursor;
      this.error = undefined;
    } catch (e) {
      this.error = (e as Error).message;
    } finally {
      this.loading = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.nextCursor) {
      return;
    }
    await this.attempt(async () => {
      const page = await this.client().list({...this.query(), limit: this.pageSize, cursor: this.nextCursor});
      this.items = [...this.items, ...page.items.filter((n) => !this.items.some((i) => i.id === n.id))];
      this.nextCursor = page.nextCursor;
    });
  }

  // Runs an action and shows its failure instead of leaving an unhandled rejection.
  private async attempt(action: () => Promise<void>): Promise<void> {
    try {
      await action();
      this.error = undefined;
    } catch (e) {
      this.error = (e as Error).message;
    }
  }

  // Left and right arrows move between the tabs.
  private arrow(e: KeyboardEvent): void {
    if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") {
      return;
    }
    const index = BOXES.findIndex((b) => b.box === this.box);
    const next = BOXES[(index + (e.key === "ArrowRight" ? 1 : BOXES.length - 1)) % BOXES.length];
    this.box = next.box;
    void this.updateComplete.then(() => (this.renderRoot.querySelector(".tab[aria-selected=true]") as HTMLElement | null)?.focus());
  }

  private query(): ListOptions {
    return {box: this.box, read: this.unreadOnly ? false : undefined, severity: this.severity || undefined,
      correlationId: this.correlationId || undefined};
  }

  private client(): NotificationClient {
    return new NotificationClient(this.baseUrl, this.auth);
  }

  private start(): void {
    this.unsubscribe?.();
    this.unsubscribe = feedFor(this.baseUrl, this.auth).subscribe((change) => this.apply(change));
    void this.reload();
  }

  private apply(change: FeedChange): void {
    switch (change.type) {
      case "created":
        if (this.inBox(change.notification) && !this.items.some((n) => n.id === change.notification.id)) {
          this.items = [change.notification, ...this.items];
        }
        break;
      case "read":
      case "unread":
        if (this.unreadOnly && change.type === "read") {
          this.items = this.items.filter((n) => n.id !== change.id);
          break;
        }
        this.items = this.items.map((n) => n.id === change.id
            ? {...n, read: change.type === "read", readAt: change.type === "read" ? change.readAt : undefined} : n);
        break;
      case "deleted":
        this.items = this.items.filter((n) => n.id !== change.id);
        break;
      default:
        void this.reload();
    }
  }

  private inBox(n: Notification): boolean {
    const box = this.box === "all" || (this.box === "personal") === (n.recipientType === "USER");
    return box && (!this.severity || n.severity === this.severity)
        && (!this.correlationId || n.correlationId === this.correlationId);
  }

  private async open(n: Notification): Promise<void> {
    const event = new CustomEvent("commons-notification-click",
        {detail: {notification: n}, bubbles: true, composed: true, cancelable: true});
    if (this.dispatchEvent(event) && !n.read) {
      await this.setRead(n, true);
    }
  }

  private async setRead(n: Notification, read: boolean): Promise<void> {
    await this.attempt(async () => {
      const updated = read ? await this.client().markRead(n.id) : await this.client().markUnread(n.id);
      this.items = this.items.map((item) => item.id === n.id ? updated : item);
    });
  }

  // Marks what the filters show. The service filters read-all by box and correlation ID but not by severity, so a
  // severity filter marks the loaded notifications one by one.
  private async markAll(): Promise<void> {
    await this.attempt(async () => {
      if (this.severity) {
        await Promise.all(this.items.filter((n) => !n.read).map((n) => this.client().markRead(n.id)));
      } else {
        await this.client().markAllRead({box: this.box, correlationId: this.correlationId || undefined});
      }
    });
    await this.reload();
  }

  override render() {
    return html`
      <header part="header">
        ${this.hideTabs ? nothing : html`<span role="tablist" aria-label="Boxes" class="tabs">${BOXES.map(({box, label}) => html`
          <button class="tab" role="tab" aria-selected=${this.box === box} tabindex=${this.box === box ? 0 : -1}
              @click=${() => { this.box = box; }} @keydown=${(e: KeyboardEvent) => this.arrow(e)}>
            ${label}</button>`)}</span>`}
        ${this.showFilters ? html`<span class="filters" part="filters">
          <label><input type="checkbox" .checked=${this.unreadOnly}
              @change=${(e: Event) => { this.unreadOnly = (e.target as HTMLInputElement).checked; }}> Unread</label>
          <select aria-label="Severity" @change=${(e: Event) => {
              this.severity = ((e.target as HTMLSelectElement).value || undefined) as Severity | undefined; }}>
            ${["", "INFO", "WARNING", "ERROR", "SUCCESS"].map((v) => html`<option value=${v}
                ?selected=${(this.severity ?? "") === v}>${v ? v.toLowerCase() : "any severity"}</option>`)}
          </select></span>` : nothing}
        <button class="link" part="mark-all" @click=${() => this.markAll()}>Mark all read</button>
      </header>
      ${this.error ? html`<div class="error" role="alert">${this.error}</div>` : nothing}
      ${!this.loading && !this.error && this.items.length === 0
          ? html`<div class="empty" part="empty"><slot name="empty">No notifications.</slot></div>` : nothing}
      <ul part="list" aria-label="Notifications">
        ${this.items.map((n) => html`
          <li class="${n.severity} ${n.read ? "read" : ""}" part="item" tabindex="0"
              @click=${() => this.open(n)} @keydown=${(e: KeyboardEvent) => e.key === "Enter" && this.open(n)}>
            <span class="title">${n.title}</span>
            ${n.read ? html`<span></span>` : html`<span class="unread-dot" aria-label="unread"></span>`}
            ${n.body ? html`<span class="body">${n.body}</span>` : nothing}
            <span class="meta">
              <span>${n.recipientType === "ROLE" ? `Role ${n.recipientId}` : "Personal"}</span>
              <span title=${n.createdAt}>${relativeTime(n.createdAt)}</span>
              <button class="toggle" @click=${(e: Event) => { e.stopPropagation(); void this.setRead(n, !n.read); }}>
                ${n.read ? "Mark unread" : "Mark read"}</button>
            </span>
          </li>`)}
      </ul>
      ${this.nextCursor ? html`<button class="more" @click=${() => this.loadMore()}>Load more</button>` : nothing}
    `;
  }
}

if (!customElements.get("commons-inbox")) {
  customElements.define("commons-inbox", CommonsInbox);
}

declare global {
  interface HTMLElementTagNameMap {
    "commons-inbox": CommonsInbox;
  }
}
