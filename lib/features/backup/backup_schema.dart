// Fixed application-owned schemas. Never execute schema SQL supplied by a backup.
import 'dart:convert';

final List<Map<String, dynamic>> backupSpecs = (jsonDecode(r'''[
  {
    "name": "daynest.db",
    "version": 2,
    "tables": {
      "journal_entries": [
        "id",
        "title",
        "content",
        "improvement",
        "reflection",
        "entry_date",
        "mood",
        "tags_json",
        "photos_json",
        "rich_text",
        "deleted_at",
        "updated_at"
      ],
      "journal_drafts": [
        "draft_key",
        "payload",
        "updated_at"
      ],
      "journal_meta": [
        "meta_key",
        "value"
      ]
    },
    "create": [
      "CREATE TABLE journal_entries (\n            id INTEGER PRIMARY KEY AUTOINCREMENT,\n            title TEXT NOT NULL,\n            content TEXT NOT NULL,\n            improvement TEXT NOT NULL,\n            reflection TEXT NOT NULL,\n            entry_date TEXT NOT NULL\n          , mood TEXT NOT NULL DEFAULT '', tags_json TEXT NOT NULL DEFAULT '[]', photos_json TEXT NOT NULL DEFAULT '[]', rich_text TEXT, deleted_at TEXT, updated_at TEXT NOT NULL DEFAULT '')",
      "CREATE TABLE journal_drafts (\n      draft_key TEXT PRIMARY KEY,\n      payload TEXT NOT NULL,\n      updated_at TEXT NOT NULL\n    )",
      "CREATE TABLE journal_meta (\n      meta_key TEXT PRIMARY KEY,\n      value TEXT NOT NULL\n    )"
    ],
    "after": [
      "CREATE INDEX journal_date_index ON journal_entries(entry_date)"
    ]
  },
  {
    "name": "daynest_money.db",
    "version": 2,
    "tables": {
      "money_transactions": [
        "id",
        "title",
        "amount",
        "flow",
        "category",
        "entry_date",
        "note",
        "payment_method",
        "payment_source"
      ],
      "money_people": [
        "id",
        "title",
        "amount",
        "flow",
        "entry_date",
        "note",
        "settled"
      ],
      "money_bills": [
        "id",
        "title",
        "amount",
        "entry_date",
        "note",
        "paid",
        "transaction_id"
      ]
    },
    "create": [
      "CREATE TABLE money_transactions (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,\n        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),\n        flow TEXT NOT NULL CHECK(flow IN ('income','expense')),\n        category TEXT NOT NULL,\n        entry_date TEXT NOT NULL,\n        note TEXT NOT NULL DEFAULT '',\n        payment_method TEXT NOT NULL DEFAULT '',\n        payment_source TEXT NOT NULL DEFAULT ''\n      )",
      "CREATE TABLE money_people (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,\n        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),\n        flow TEXT NOT NULL CHECK(flow IN ('receivable','payable')),\n        entry_date TEXT NOT NULL,\n        note TEXT NOT NULL DEFAULT '',\n        settled INTEGER NOT NULL DEFAULT 0 CHECK(settled IN (0,1))\n      )",
      "CREATE TABLE money_bills (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,\n        amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 100000000000),\n        entry_date TEXT NOT NULL,\n        note TEXT NOT NULL DEFAULT '',\n        paid INTEGER NOT NULL DEFAULT 0 CHECK(paid IN (0,1)),\n        transaction_id INTEGER UNIQUE REFERENCES money_transactions(id),\n        CHECK((paid = 0 AND transaction_id IS NULL) OR\n              (paid = 1 AND transaction_id IS NOT NULL))\n      )"
    ],
    "after": [
      "CREATE INDEX money_date ON money_transactions(entry_date)"
    ]
  },
  {
    "name": "daynest_tasks.db",
    "version": 3,
    "tables": {
      "tasks": [
        "id",
        "title",
        "note",
        "due_date",
        "due_minutes",
        "priority",
        "category",
        "done",
        "checklist",
        "deleted",
        "completed_at",
        "reminder_minutes"
      ]
    },
    "create": [
      "CREATE TABLE tasks (\n        id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL CHECK(length(trim(title)) > 0),\n        note TEXT NOT NULL DEFAULT '',\n        due_date TEXT,\n        due_minutes INTEGER CHECK(due_minutes IS NULL OR due_minutes BETWEEN 0 AND 1439),\n        priority TEXT NOT NULL DEFAULT 'Normal' CHECK(priority IN ('High','Normal','Low')),\n        category TEXT NOT NULL DEFAULT '',\n        done INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0,1)),\n        checklist TEXT NOT NULL DEFAULT '[]',\n        deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),\n        completed_at TEXT,\n        reminder_minutes INTEGER CHECK(reminder_minutes IS NULL OR reminder_minutes IN (0,10,60)),\n        CHECK(due_date IS NOT NULL OR due_minutes IS NULL)\n      )"
    ],
    "after": [
      "CREATE INDEX tasks_due ON tasks(deleted,done,due_date)",
      "CREATE TRIGGER tasks_completed_insert AFTER INSERT ON tasks\n      WHEN NEW.done=1 BEGIN UPDATE tasks SET completed_at=strftime('%Y-%m-%dT%H:%M:%f','now','localtime') WHERE id=NEW.id; END",
      "CREATE TRIGGER tasks_completed_update AFTER UPDATE OF done ON tasks\n      WHEN NEW.done<>OLD.done BEGIN UPDATE tasks SET completed_at=CASE WHEN NEW.done=1\n      THEN strftime('%Y-%m-%dT%H:%M:%f','now','localtime') ELSE NULL END WHERE id=NEW.id; END"
    ]
  },
  {
    "name": "daynest_more.db",
    "version": 1,
    "tables": {
      "folders": [
        "id",
        "kind",
        "name"
      ],
      "notes": [
        "id",
        "title",
        "content",
        "folder_id",
        "pinned",
        "deleted",
        "updated_at"
      ],
      "documents": [
        "id",
        "title",
        "file_name",
        "original_name",
        "size",
        "folder_id",
        "starred",
        "note",
        "expires",
        "deleted",
        "created_at"
      ],
      "preferences": [
        "name",
        "value"
      ],
      "vault_meta": [
        "id",
        "payload"
      ],
      "vault_entries": [
        "id",
        "payload"
      ]
    },
    "create": [
      "CREATE TABLE folders(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,name TEXT NOT NULL,UNIQUE(kind,name))",
      "CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,\n        content TEXT NOT NULL DEFAULT '',folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,\n        pinned INTEGER NOT NULL DEFAULT 0,deleted INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL)",
      "CREATE TABLE documents(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,\n        file_name TEXT NOT NULL UNIQUE,original_name TEXT NOT NULL,size INTEGER NOT NULL,\n        folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,starred INTEGER NOT NULL DEFAULT 0,\n        note TEXT NOT NULL DEFAULT '',expires TEXT,deleted INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL)",
      "CREATE TABLE preferences(name TEXT PRIMARY KEY,value TEXT NOT NULL)",
      "CREATE TABLE vault_meta(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL)",
      "CREATE TABLE vault_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,payload TEXT NOT NULL)"
    ],
    "after": []
  },
  {
    "name": "daynest_progress.db",
    "version": 1,
    "tables": {
      "habits": [
        "id",
        "title",
        "category",
        "created_on",
        "archived_on"
      ],
      "habit_logs": [
        "habit_id",
        "day"
      ],
      "goals": [
        "id",
        "title",
        "unit",
        "target",
        "current",
        "period",
        "start_on",
        "end_on"
      ]
    },
    "create": [
      "CREATE TABLE habits(id INTEGER PRIMARY KEY AUTOINCREMENT,\n        title TEXT NOT NULL,category TEXT NOT NULL CHECK(category IN ('Mind','Body','Growth')),\n        created_on TEXT NOT NULL,archived_on TEXT)",
      "CREATE TABLE habit_logs(habit_id INTEGER NOT NULL REFERENCES habits(id),\n        day TEXT NOT NULL,PRIMARY KEY(habit_id,day))",
      "CREATE TABLE goals(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,\n        unit TEXT NOT NULL,target REAL NOT NULL CHECK(target>0),current REAL NOT NULL DEFAULT 0 CHECK(current>=0),\n        period TEXT NOT NULL,start_on TEXT NOT NULL,end_on TEXT NOT NULL)"
    ],
    "after": []
  }
]''') as List).map((v) => Map<String, dynamic>.from(v as Map)).toList();
