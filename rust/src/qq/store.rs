//! SQLite：接口响应缓存、歌曲缓存索引 + 登录态等键值存储。

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

/// 同一秒内连续播放的歌也要分得出先后。
fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as i64
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
             CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
             CREATE TABLE IF NOT EXISTS audio_cache (
                 mid TEXT NOT NULL, quality TEXT NOT NULL, file TEXT NOT NULL,
                 size INTEGER NOT NULL, last_used INTEGER NOT NULL,
                 PRIMARY KEY (mid, quality));",
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

    /// 接口缓存占用的字节数（只算内容）。
    pub fn cache_size(&self) -> i64 {
        let conn = self.conn.lock().unwrap();
        conn.query_row("SELECT COALESCE(SUM(LENGTH(key) + LENGTH(value)), 0) FROM cache", [], |r| r.get(0))
            .unwrap_or(0)
    }

    /// 查歌曲缓存文件名，命中时更新最近使用时间。
    pub fn audio_get(&self, mid: &str, quality: &str) -> Option<String> {
        let conn = self.conn.lock().unwrap();
        let file: Option<String> = conn
            .query_row(
                "SELECT file FROM audio_cache WHERE mid = ?1 AND quality = ?2",
                params![mid, quality],
                |r| r.get(0),
            )
            .optional()
            .ok()
            .flatten();
        if file.is_some() {
            let _ = conn.execute(
                "UPDATE audio_cache SET last_used = ?3 WHERE mid = ?1 AND quality = ?2",
                params![mid, quality, now_ms()],
            );
        }
        file
    }

    /// 这首歌缓存过的所有音质，最近听的在前：(音质, 文件名)。
    pub fn audio_of(&self, mid: &str) -> Vec<(String, String)> {
        let conn = self.conn.lock().unwrap();
        let Ok(mut stmt) =
            conn.prepare("SELECT quality, file FROM audio_cache WHERE mid = ?1 ORDER BY last_used DESC")
        else {
            return vec![];
        };
        stmt.query_map(params![mid], |r| Ok((r.get(0)?, r.get(1)?)))
            .map(|rows| rows.flatten().collect())
            .unwrap_or_default()
    }

    pub fn audio_put(&self, mid: &str, quality: &str, file: &str, size: i64) -> Result<()> {
        self.conn.lock().unwrap().execute(
            "INSERT OR REPLACE INTO audio_cache (mid, quality, file, size, last_used) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![mid, quality, file, size, now_ms()],
        )?;
        Ok(())
    }

    pub fn audio_delete(&self, mid: &str, quality: &str) {
        let _ = self.conn.lock().unwrap().execute(
            "DELETE FROM audio_cache WHERE mid = ?1 AND quality = ?2",
            params![mid, quality],
        );
    }

    pub fn audio_total(&self) -> i64 {
        let conn = self.conn.lock().unwrap();
        conn.query_row("SELECT COALESCE(SUM(size), 0) FROM audio_cache", [], |r| r.get(0)).unwrap_or(0)
    }

    /// 全部歌曲缓存，最久没听的在前：(mid, 音质, 文件名, 大小)。
    pub fn audio_lru(&self) -> Vec<(String, String, String, i64)> {
        let conn = self.conn.lock().unwrap();
        let Ok(mut stmt) = conn.prepare("SELECT mid, quality, file, size FROM audio_cache ORDER BY last_used")
        else {
            return vec![];
        };
        stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
            .map(|rows| rows.flatten().collect())
            .unwrap_or_default()
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
