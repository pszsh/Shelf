use rusqlite::Row;

#[derive(Debug, Clone)]
pub struct Clip {
    pub id: String,
    pub timestamp: f64,
    pub content_type: ContentType,
    pub text_content: Option<String>,
    pub image_path: Option<String>,
    pub source_app: Option<String>,
    pub is_pinned: bool,
    pub displaced_prev: Option<i64>,
    pub displaced_next: Option<i64>,
    pub source_path: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum ContentType {
    Text = 0,
    Url = 1,
    Image = 2,
}

impl ContentType {
    pub fn from_str(s: &str) -> Self {
        match s {
            "url" => Self::Url,
            "image" => Self::Image,
            _ => Self::Text,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Text => "text",
            Self::Url => "url",
            Self::Image => "image",
        }
    }

    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::Url,
            2 => Self::Image,
            _ => Self::Text,
        }
    }
}

impl Clip {
    pub fn from_row(row: &Row) -> rusqlite::Result<Self> {
        let ct_str: String = row.get(2)?;
        Ok(Clip {
            id: row.get(0)?,
            timestamp: row.get(1)?,
            content_type: ContentType::from_str(&ct_str),
            text_content: row.get(3)?,
            image_path: row.get(4)?,
            source_app: row.get(5)?,
            is_pinned: row.get::<_, i32>(6)? != 0,
            displaced_prev: row.get(7)?,
            displaced_next: row.get(8)?,
            source_path: row.get(9)?,
        })
    }
}
