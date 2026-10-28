//! SQLite：接口响应缓存 + 登录态等键值存储。

use std::path::Path;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};

pub struct Store {
    conn: Mutex<Connection>,
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)?;
        Self::init(conn)
    }

    pub fn in_memory() -> Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> Result<Self> {
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, expires_at INTEGER NOT NULL);
             CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        )?;
        conn.execute("DELETE FROM cache WHERE expires_at < ?1", params![now()])?;
        Ok(Self { conn: Mutex::new(conn) })
    }

    pub fn cache_get(&self, key: &str) -> Option<String> {
        let conn = self.conn.lock().unwrap();
        conn.query_row(
            "SELECT value FROM cache WHERE key = ?1 AND expires_at >= ?2",
            params![key, now()],
            |r| r.get(0),
        )
        .optional()
        .ok()
        .flatten()
    }

    pub fn cache_put(&self, key: &str, value: &str, ttl_secs: i64) {
        let conn = self.conn.lock().unwrap();
        let _ = conn.execute(
            "INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?1, ?2, ?3)",
            params![key, value, now() + ttl_secs],
        );
    }

    pub fn cache_delete(&self, key: &str) {
        let _ = self.conn.lock().unwrap().execute("DELETE FROM cache WHERE key = ?1", params![key]);
    }

    pub fn cache_clear(&self) -> Result<()> {
        self.conn.lock().unwrap().execute("DELETE FROM cache", [])?;
        Ok(())
    }

    pub fn kv_get(&self, key: &str) -> Option<String> {
        let conn = self.conn.lock().unwrap();
        conn.query_row("SELECT value FROM kv WHERE key = ?1", params![key], |r| r.get(0))
            .optional()
            .ok()
            .flatten()
    }

    pub fn kv_set(&self, key: &str, value: &str) -> Result<()> {
        self.conn.lock().unwrap().execute(
            "INSERT OR REPLACE INTO kv (key, value) VALUES (?1, ?2)",
            params![key, value],
        )?;
        Ok(())
    }

    pub fn kv_delete(&self, key: &str) -> Result<()> {
        self.conn.lock().unwrap().execute("DELETE FROM kv WHERE key = ?1", params![key])?;
        Ok(())
    }
}
