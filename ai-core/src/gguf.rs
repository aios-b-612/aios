//! GGUF model file header/metadata parser (pure Rust, no external deps).
//!
//! Format (little-endian):
//!   magic        u32    = 0x46554747 ("GGUF")
//!   version      u32
//!   tensor_count u64
//!   metadata_kv_count u64
//!   metadata: repeated (key, value_type u32, value)

use crate::error::{Error, Result};

pub const GGUF_MAGIC: u32 = 0x4655_4747;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum ValueType {
    Uint8 = 0,
    Int8 = 1,
    Uint16 = 2,
    Int16 = 3,
    Uint32 = 4,
    Int32 = 5,
    Float32 = 6,
    Bool = 7,
    String = 8,
    Array = 9,
    Uint64 = 10,
    Int64 = 11,
    Float64 = 12,
    Unknown(u32),
}

impl From<u32> for ValueType {
    fn from(v: u32) -> Self {
        match v {
            0 => ValueType::Uint8,
            1 => ValueType::Int8,
            2 => ValueType::Uint16,
            3 => ValueType::Int16,
            4 => ValueType::Uint32,
            5 => ValueType::Int32,
            6 => ValueType::Float32,
            7 => ValueType::Bool,
            8 => ValueType::String,
            9 => ValueType::Array,
            10 => ValueType::Uint64,
            11 => ValueType::Int64,
            12 => ValueType::Float64,
            other => ValueType::Unknown(other),
        }
    }
}

impl ValueType {
    pub fn name(&self) -> String {
        format!("{self:?}")
    }
}

#[derive(Debug, Clone)]
pub enum Value {
    Uint8(u8),
    Int8(i8),
    Uint16(u16),
    Int16(i16),
    Uint32(u32),
    Int32(i32),
    Float32(f32),
    Bool(bool),
    String(String),
    Array(Vec<Value>),
    Uint64(u64),
    Int64(i64),
    Float64(f64),
    Unknown(u32, Vec<u8>),
}

impl Value {
    /// Compact human-readable form, e.g. for `ai inspect`.
    pub fn brief(&self) -> String {
        match self {
            Value::String(s) => format!("\"{s}\""),
            Value::Array(items) => format!(
                "[{}]",
                items
                    .iter()
                    .take(8)
                    .map(|v| v.brief())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            Value::Bool(b) => b.to_string(),
            Value::Unknown(t, bytes) => format!("<unknown type {t}: {} bytes>", bytes.len()),
            other => format!("{other:?}"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Metadata {
    pub key: String,
    pub value_type: ValueType,
    pub value: Value,
}

/// Header of a GGUF file plus its parsed metadata entries.
#[derive(Debug, Clone)]
pub struct GgufHeader {
    pub version: u32,
    pub tensor_count: u64,
    pub metadata: Vec<Metadata>,
}

impl GgufHeader {
    /// Find a metadata entry by key (first match).
    pub fn get(&self, key: &str) -> Option<&Metadata> {
        self.metadata.iter().find(|m| m.key == key)
    }

    /// Convenience getters used by the model registry.
    pub fn general_name(&self) -> Option<String> {
        match self.get("general.name") {
            Some(Metadata {
                value: Value::String(s),
                ..
            }) => Some(s.clone()),
            _ => None,
        }
    }

    pub fn general_file_type(&self) -> Option<u32> {
        match self.get("general.file_type") {
            Some(Metadata {
                value: Value::Uint32(v),
                ..
            }) => Some(*v),
            Some(Metadata {
                value: Value::Int32(v),
                ..
            }) => Some(*v as u32),
            _ => None,
        }
    }
}

/// Read the GGUF header from the first bytes of a model file.
pub fn parse_header(buf: &[u8]) -> Result<GgufHeader> {
    let mut pos = 0usize;

    let magic = read_u32(buf, &mut pos)?;
    if magic != GGUF_MAGIC {
        return Err(Error::Msg(format!(
            "invalid GGUF magic 0x{magic:08x} (expected 0x{GGUF_MAGIC:08x})"
        )));
    }
    let version = read_u32(buf, &mut pos)?;
    let tensor_count = read_u64(buf, &mut pos)?;
    let kv_count = read_u64(buf, &mut pos)?;

    let mut metadata = Vec::with_capacity(kv_count as usize);
    for _ in 0..kv_count {
        let key = read_string(buf, &mut pos)?;
        let value_type = ValueType::from(read_u32(buf, &mut pos)?);
        let value = read_value(buf, &mut pos, value_type)?;
        metadata.push(Metadata {
            key,
            value_type,
            value,
        });
    }

    Ok(GgufHeader {
        version,
        tensor_count,
        metadata,
    })
}

fn read_u32(buf: &[u8], pos: &mut usize) -> Result<u32> {
    let s = read(buf, pos, 4)?;
    Ok(u32::from_le_bytes([s[0], s[1], s[2], s[3]]))
}

fn read_u64(buf: &[u8], pos: &mut usize) -> Result<u64> {
    let s = read(buf, pos, 8)?;
    Ok(u64::from_le_bytes([
        s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7],
    ]))
}

fn read_string(buf: &[u8], pos: &mut usize) -> Result<String> {
    let len = read_u64(buf, pos)? as usize;
    let s = read(buf, pos, len)?;
    String::from_utf8(s.to_vec()).map_err(|e| Error::Msg(format!("invalid utf-8 in GGUF string: {e}")))
}

fn read_value(buf: &[u8], pos: &mut usize, vt: ValueType) -> Result<Value> {
    Ok(match vt {
        ValueType::Uint8 => Value::Uint8(read(buf, pos, 1)?[0]),
        ValueType::Int8 => Value::Int8(read(buf, pos, 1)?[0] as i8),
        ValueType::Uint16 => {
            let s = read(buf, pos, 2)?;
            Value::Uint16(u16::from_le_bytes([s[0], s[1]]))
        }
        ValueType::Int16 => {
            let s = read(buf, pos, 2)?;
            Value::Int16(i16::from_le_bytes([s[0], s[1]]))
        }
        ValueType::Uint32 => Value::Uint32(read_u32(buf, pos)?),
        ValueType::Int32 => Value::Int32(read_u32(buf, pos)? as i32),
        ValueType::Float32 => Value::Float32(f32::from_bits(read_u32(buf, pos)?)),
        ValueType::Bool => Value::Bool(read(buf, pos, 1)?[0] != 0),
        ValueType::String => Value::String(read_string(buf, pos)?),
        ValueType::Array => {
            let elem_type = ValueType::from(read_u32(buf, pos)?);
            let count = read_u64(buf, pos)?;
            let mut items = Vec::with_capacity(count as usize);
            for _ in 0..count {
                items.push(read_value(buf, pos, elem_type)?);
            }
            Value::Array(items)
        }
        ValueType::Uint64 => Value::Uint64(read_u64(buf, pos)?),
        ValueType::Int64 => Value::Int64(read_u64(buf, pos)? as i64),
        ValueType::Float64 => Value::Float64(f64::from_bits(read_u64(buf, pos)?)),
        ValueType::Unknown(t, ..) => {
            // Unknown type: skip its body conservatively (16 bytes). GGUF is
            // versioned; newer types keep fixed-size scalars.
            let bytes = read(buf, pos, 16)?.to_vec();
            Value::Unknown(t, bytes)
        }
    })
}

fn read<'a>(buf: &'a [u8], pos: &mut usize, len: usize) -> Result<&'a [u8]> {
    let end = pos
        .checked_add(len)
        .ok_or_else(|| Error::Msg("GGUF length overflow".to_string()))?;
    if end > buf.len() {
        return Err(Error::Msg(format!(
            "truncated GGUF (need {len} bytes at offset {pos}, file has {})",
            buf.len()
        )));
    }
    *pos = end;
    Ok(&buf[*pos - len..*pos])
}