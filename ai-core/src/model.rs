//! Model metadata + helpers to describe a model on disk.

use crate::error::Result;
use crate::gguf::{self, GgufHeader};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct ModelMeta {
    /// Canonical name: file stem, or `general.name` when present.
    pub name: String,
    /// Path to the GGUF file.
    pub path: String,
    /// Size in bytes.
    pub size_bytes: u64,
    /// GGUF header (parsed on demand; `None` if the file is not GGUF).
    pub header: Option<GgufHeader>,
}

impl ModelMeta {
    /// Read metadata from a GGUF file without loading the whole file: the
    /// header is read from the first ~KiB (metadata usually fits there).
    pub fn from_path(path: &Path) -> Result<Self> {
        let meta = fs::metadata(path)?;
        let size_bytes = meta.len();

        let name = file_stem(path).unwrap_or_else(|| path.display().to_string());

        let header = read_header_head(path)?;

        Ok(ModelMeta {
            name,
            path: path.display().to_string(),
            size_bytes,
            header,
        })
    }

    pub fn is_gguf(&self) -> bool {
        self.header.is_some()
    }

    /// Pretty size, e.g. "930.4 MiB".
    pub fn size_pretty(&self) -> String {
        pretty_bytes(self.size_bytes)
    }
}

/// Read enough of the file to parse the GGUF header. ggml files used to have
/// the metadata block at the end; modern GGUF puts it at the start and it is
/// small. We read the first 1 MiB, which covers virtually all headers.
fn read_header_head(path: &Path) -> Result<Option<GgufHeader>> {
    use std::io::Read;
    let mut f = fs::File::open(path)?;
    let mut buf = Vec::with_capacity(1 << 20);
    f.by_ref().take(1 << 20).read_to_end(&mut buf)?;

    if buf.get(0..4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]])) != Some(gguf::GGUF_MAGIC) {
        return Ok(None);
    }
    gguf::parse_header(&buf).map(Some)
}

pub fn file_stem(path: &Path) -> Option<String> {
    path.file_stem()
        .and_then(|s| s.to_str())
        .map(|s| s.to_string())
}

pub fn pretty_bytes(bytes: u64) -> String {
    const KIB: f64 = 1024.0;
    let b = bytes as f64;
    if b >= KIB * KIB * KIB {
        format!("{:.1} GiB", b / (KIB * KIB * KIB))
    } else if b >= KIB * KIB {
        format!("{:.1} MiB", b / (KIB * KIB))
    } else if b >= KIB {
        format!("{:.1} KiB", b / KIB)
    } else {
        format!("{b} B")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes() {
        assert_eq!(pretty_bytes(0), "0 B");
        assert_eq!(pretty_bytes(1024), "1.0 KiB");
        assert_eq!(pretty_bytes(953_675_776), "909.5 MiB");
        assert_eq!(pretty_bytes((1024.0 * 1024.0 * 1024.0) as u64), "1.0 GiB");
    }
}