import {type AuthAdapter, tokens} from "@bal-commons/ui-core";
import {css, html, LitElement} from "lit";
import {NotificationClient} from "./client.js";
import {feedFor} from "./feed.js";

/**
 * A bell with the caller's unread count, kept live.
 * @fires commons-bell-click - The bell was clicked.
 * @csspart button - The bell button.
 * @csspart badge - The unread count.
 */
export class CommonsNotificationBell extends LitElement {
  static override properties = {
    baseUrl: {type: String, attribute: "base-url"},
    auth: {attribute: false},
    label: {type: String},
    count: {state: true, attribute: false}
  };

  declare baseUrl: string;
  declare auth?: AuthAdapter;
  declare label: string;
  /** @internal */
  declare count: number;
  private unsubscribe?: () => void;

  constructor() {
    super();
    this.baseUrl = "";
    this.label = "Notifications";
    this.count = 0;
  }

  static override styles = [tokens, css`
    :host { display: inline-block; }
    button {
      position: relative; display: inline-flex; align-items: center; justify-content: center;
      width: 40px; height: 40px; border-radius: 50%; border: 1px solid var(--_border);
      background: var(--_bg); color: var(--_fg); cursor: pointer;
    }
    button:focus-visible { outline: 2px solid var(--_accent); outline-offset: 2px; }
    svg { width: 20px; height: 20px; }
    .badge {
      position: absolute; top: -4px; right: -4px; min-width: 18px; height: 18px; padding: 0 5px;
      border-radius: 9px; background: var(--_error); color: #fff; font-size: 11px; line-height: 18px;
      font-weight: 600; box-sizing: border-box;
    }
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
    if (changed.has("baseUrl") && this.baseUrl && this.isConnected) {
      this.start();
    }
  }

  // Refetches the count; call it after marking notifications read elsewhere.
  async refresh(): Promise<void> {
    try {
      this.count = (await new NotificationClient(this.baseUrl, this.auth).unreadCount()).total;
    } catch {
      // Keep the last known count; the stream reconnects on its own.
    }
  }

  private start(): void {
    this.unsubscribe?.();
    this.unsubscribe = feedFor(this.baseUrl, this.auth).subscribe(() => void this.refresh());
    void this.refresh();
  }

  override render() {
    const text = this.count > 99 ? "99+" : String(this.count);
    return html`<button part="button" aria-label="${this.label}${this.count ? `, ${this.count} unread` : ""}"
        @click=${() => this.dispatchEvent(new CustomEvent("commons-bell-click", {bubbles: true, composed: true}))}>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"
          stroke-linejoin="round" aria-hidden="true">
        <path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"></path><path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
      </svg>
      ${this.count ? html`<span class="badge" part="badge">${text}</span>` : null}
    </button>`;
  }
}

if (!customElements.get("commons-notification-bell")) {
  customElements.define("commons-notification-bell", CommonsNotificationBell);
}

declare global {
  interface HTMLElementTagNameMap {
    "commons-notification-bell": CommonsNotificationBell;
  }
}
