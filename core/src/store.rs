use crate::clip::{Clip, ContentType};
use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};

pub struct Store {
    conn: Connection,
    image_dir: PathBuf,
    max_items: usize,
}

impl Store {
    pub fn new(support_dir: &str, max_items: usize) -> Self {
        let support = Path::new(support_dir);
        let image_dir = support.join("images");
        fs::create_dir_all(support).ok();
        fs::create_dir_all(&image_dir).ok();

        let db_path = support.join("clips.db");
        let conn = Connection::open(&db_path).expect("failed to open database");

        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                content_type TEXT NOT NULL,
                text_content TEXT,
                image_path TEXT,
                source_app TEXT,
                is_pinned INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_timestamp ON clips(timestamp DESC);",
        )
        .expect("failed to create schema");

        conn.execute("ALTER TABLE clips ADD COLUMN displaced_prev INTEGER", []).ok();
        conn.execute("ALTER TABLE clips ADD COLUMN displaced_next INTEGER", []).ok();
        conn.execute("ALTER TABLE clips ADD COLUMN source_path TEXT", []).ok();

        Store {
            conn,
            image_dir,
            max_items,
        }
    }

    pub fn get_all(&self) -> Vec<Clip> {
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, timestamp, content_type, text_content, image_path, source_app, is_pinned,
                        displaced_prev, displaced_next, source_path
                 FROM clips ORDER BY is_pinned DESC, timestamp DESC",
            )
            .unwrap();

        stmt.query_map([], |row| Clip::from_row(row))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect()
    }

    pub fn add(&self, clip: &Clip, image_data: Option<&[u8]>) -> Option<String> {
        if let Some(existing_id) = self.find_duplicate(clip) {
            let ordered: Vec<String> = self
                .conn
                .prepare("SELECT id FROM clips ORDER BY is_pinned DESC, timestamp DESC")
                .unwrap()
                .query_map([], |row| row.get(0))
                .unwrap()
                .filter_map(|r| r.ok())
                .collect();

            if let Some(pos) = ordered.iter().position(|id| *id == existing_id) {
                if pos == 0 {
                    return None;
                }
                let prev: Option<i64> = Some(pos as i64);
                let next: Option<i64> =
                    if pos + 1 < ordered.len() { Some((pos + 1) as i64) } else { None };

                self.conn
                    .execute(
                        "UPDATE clips SET timestamp = ?1, source_app = ?2,
                         displaced_prev = ?3, displaced_next = ?4 WHERE id = ?5",
                        rusqlite::params![clip.timestamp, clip.source_app, prev, next, existing_id],
                    )
                    .ok();
            }
            return None;
        }

        let image_path = if clip.content_type == ContentType::Image {
            image_data.and_then(|data| {
                let filename = format!("{}.png", clip.id);
                let path = self.image_dir.join(&filename);
                fs::write(&path, data).ok()?;
                Some(path.to_string_lossy().into_owned())
            })
        } else {
            None
        };

        self.conn
            .execute(
                "INSERT OR REPLACE INTO clips
                 (id, timestamp, content_type, text_content, image_path, source_app, is_pinned, source_path)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                rusqlite::params![
                    clip.id,
                    clip.timestamp,
                    clip.content_type.as_str(),
                    clip.text_content,
                    image_path,
                    clip.source_app,
                    clip.is_pinned as i32,
                    clip.source_path,
                ],
            )
            .ok();

        self.prune_excess();
        image_path
    }

    pub fn delete(&self, id: &str) {
        if let Ok(path) = self.conn.query_row(
            "SELECT image_path FROM clips WHERE id = ?1",
            [id],
            |row| row.get::<_, Option<String>>(0),
        ) {
            if let Some(p) = path {
                fs::remove_file(&p).ok();
            }
        }
        self.conn
            .execute("DELETE FROM clips WHERE id = ?1", [id])
            .ok();
    }

    pub fn toggle_pin(&self, id: &str) -> bool {
        let current: bool = self
            .conn
            .query_row(
                "SELECT is_pinned FROM clips WHERE id = ?1",
                [id],
                |row| Ok(row.get::<_, i32>(0)? != 0),
            )
            .unwrap_or(false);

        let new_val = !current;
        self.conn
            .execute(
                "UPDATE clips SET is_pinned = ?1 WHERE id = ?2",
                rusqlite::params![new_val as i32, id],
            )
            .ok();
        new_val
    }

    pub fn clear_all(&self) {
        if let Ok(entries) = fs::read_dir(&self.image_dir) {
            for entry in entries.flatten() {
                fs::remove_file(entry.path()).ok();
            }
        }
        self.conn.execute("DELETE FROM clips", []).ok();
    }

    fn find_duplicate(&self, clip: &Clip) -> Option<String> {
        if clip.content_type == ContentType::Image {
            return None;
        }
        let text = clip.text_content.as_ref()?;

        self.conn
            .query_row(
                "SELECT id FROM clips WHERE content_type = ?1 AND text_content = ?2 LIMIT 1",
                rusqlite::params![clip.content_type.as_str(), text],
                |row| row.get(0),
            )
            .ok()
    }

    fn prune_excess(&self) {
        let count: i64 = self
            .conn
            .query_row(
                "SELECT COUNT(*) FROM clips WHERE is_pinned = 0",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        if (count as usize) <= self.max_items {
            return;
        }

        let excess = count as usize - self.max_items;
        let mut stmt = self
            .conn
            .prepare(
                "SELECT id, image_path FROM clips
                 WHERE is_pinned = 0 ORDER BY timestamp ASC LIMIT ?1",
            )
            .unwrap();

        let to_remove: Vec<(String, Option<String>)> = stmt
            .query_map([excess as i64], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();

        for (id, path) in &to_remove {
            if let Some(p) = path {
                fs::remove_file(p).ok();
            }
            self.conn
                .execute("DELETE FROM clips WHERE id = ?1", [id])
                .ok();
        }
    }
}
