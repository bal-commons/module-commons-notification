import commons/service_commons.db as sdb;

final sdb:Migration[] & readonly migrations = [
    {
        version: 1,
        description: "notifications and per-user read state",
        statements: [
            string `CREATE TABLE {prefix}item (
                id VARCHAR(26) NOT NULL PRIMARY KEY,
                ns VARCHAR(64) NOT NULL,
                idempotency_key VARCHAR(255),
                recipient_type VARCHAR(8) NOT NULL,
                recipient_id VARCHAR(255) NOT NULL,
                severity VARCHAR(16) NOT NULL,
                category VARCHAR(128),
                title VARCHAR(500) NOT NULL,
                body TEXT,
                action_url VARCHAR(2000),
                correlation_id VARCHAR(255),
                sender VARCHAR(255),
                payload TEXT,
                created_at BIGINT NOT NULL,
                expires_at BIGINT)`,
            "CREATE INDEX {prefix}item_recipient ON {prefix}item (ns, recipient_type, recipient_id, id)",
            "CREATE INDEX {prefix}item_correlation ON {prefix}item (ns, correlation_id)",
            "CREATE INDEX {prefix}item_created ON {prefix}item (ns, created_at)",
            "CREATE UNIQUE INDEX {prefix}item_idempotency ON {prefix}item (ns, idempotency_key)",
            string `CREATE TABLE {prefix}read (
                user_id VARCHAR(255) NOT NULL,
                notification_id VARCHAR(26) NOT NULL,
                read_at BIGINT NOT NULL,
                PRIMARY KEY (user_id, notification_id))`,
            "CREATE INDEX {prefix}read_notification ON {prefix}read (notification_id)"
        ]
    }
];
