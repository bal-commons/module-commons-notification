export type Severity = "INFO" | "WARNING" | "ERROR" | "SUCCESS";
export type RecipientType = "USER" | "ROLE";
// Which of the caller's boxes a listing covers.
export type Box = "all" | "personal" | "role";

export interface Notification {
  id: string;
  recipientType: RecipientType;
  recipientId: string;
  severity: Severity;
  category?: string;
  title: string;
  body?: string;
  actionUrl?: string;
  correlationId?: string;
  sender?: string;
  payload?: unknown;
  createdAt: string;
  expiresAt?: string;
  read?: boolean;
  readAt?: string;
}

export interface NotificationPage {
  items: Notification[];
  nextCursor?: string;
}

export interface UnreadCount {
  total: number;
  personal: number;
  roles: Record<string, number>;
}

export interface ListOptions {
  box?: Box;
  role?: string;
  severity?: Severity;
  category?: string;
  correlationId?: string;
  read?: boolean;
  cursor?: string;
  limit?: number;
}
