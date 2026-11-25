use anyhow::{anyhow, bail, Context, Result};
use base64::Engine;
use serde_json::{json, Map, Number, Value};

pub const TYPE_NIL: u8 = 0;
pub const TYPE_BOOL: u8 = 1;
pub const TYPE_INT: u8 = 2;
pub const TYPE_FLOAT: u8 = 3;
pub const TYPE_STRING: u8 = 4;
pub const TYPE_VECTOR2: u8 = 5;
pub const TYPE_VECTOR2I: u8 = 6;
pub const TYPE_RECT2: u8 = 7;
pub const TYPE_RECT2I: u8 = 8;
pub const TYPE_VECTOR3: u8 = 9;
pub const TYPE_VECTOR3I: u8 = 10;
pub const TYPE_TRANSFORM2D: u8 = 11;
pub const TYPE_VECTOR4: u8 = 12;
pub const TYPE_VECTOR4I: u8 = 13;
pub const TYPE_PLANE: u8 = 14;
pub const TYPE_QUATERNION: u8 = 15;
pub const TYPE_AABB: u8 = 16;
pub const TYPE_BASIS: u8 = 17;
pub const TYPE_TRANSFORM3D: u8 = 18;
pub const TYPE_PROJECTION: u8 = 19;
pub const TYPE_COLOR: u8 = 20;
pub const TYPE_STRING_NAME: u8 = 21;
pub const TYPE_NODE_PATH: u8 = 22;
pub const TYPE_DICTIONARY: u8 = 27;
pub const TYPE_ARRAY: u8 = 28;
pub const TYPE_PACKED_BYTE_ARRAY: u8 = 29;
pub const TYPE_PACKED_INT32_ARRAY: u8 = 30;
pub const TYPE_PACKED_INT64_ARRAY: u8 = 31;
pub const TYPE_PACKED_FLOAT32_ARRAY: u8 = 32;
pub const TYPE_PACKED_FLOAT64_ARRAY: u8 = 33;
pub const TYPE_PACKED_STRING_ARRAY: u8 = 34;
pub const TYPE_PACKED_VECTOR2_ARRAY: u8 = 35;
pub const TYPE_PACKED_VECTOR3_ARRAY: u8 = 36;
pub const TYPE_PACKED_COLOR_ARRAY: u8 = 37;
pub const TYPE_PACKED_VECTOR4_ARRAY: u8 = 38;

const FLAG_64: u32 = 1 << 16;

#[derive(Debug, Clone, PartialEq)]
pub enum Variant {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(String),
    Vector2(f32, f32),
    Vector2i(i32, i32),
    Rect2(f32, f32, f32, f32),
    Rect2i(i32, i32, i32, i32),
    Vector3(f32, f32, f32),
    Vector3i(i32, i32, i32),
    Transform2D([f32; 6]),
    Vector4(f32, f32, f32, f32),
    Vector4i(i32, i32, i32, i32),
    Plane(f32, f32, f32, f32),
    Quaternion(f32, f32, f32, f32),
    Aabb([f32; 3], [f32; 3]),
    /// Basis stored as 3 column vectors [x, y, z].
    Basis([[f32; 3]; 3]),
    /// Transform3D stored as 3 basis column vectors + origin.
    Transform3D {
        basis: [[f32; 3]; 3],
        origin: [f32; 3],
    },
    Projection([f32; 16]),
    Color(f32, f32, f32, f32),
    StringName(String),
    NodePath(String),
    Dictionary(Vec<(Variant, Variant)>),
    Array(Vec<Variant>),
    PackedByteArray(Vec<u8>),
    PackedInt32Array(Vec<i32>),
    PackedInt64Array(Vec<i64>),
    PackedFloat32Array(Vec<f32>),
    PackedFloat64Array(Vec<f64>),
    PackedStringArray(Vec<String>),
    PackedVector2Array(Vec<[f32; 2]>),
    PackedVector3Array(Vec<[f32; 3]>),
    PackedColorArray(Vec<[f32; 4]>),
    PackedVector4Array(Vec<[f32; 4]>),
}

impl Variant {
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Variant::Bool(b) => Some(*b),
            Variant::Int(n) => Some(*n != 0),
            Variant::Float(f) => Some(*f != 0.0),
            _ => None,
        }
    }

    pub fn as_int(&self) -> Option<i64> {
        match self {
            Variant::Int(n) => Some(*n),
            Variant::Float(f) if f.is_finite() => Some(*f as i64),
            Variant::Bool(b) => Some(if *b { 1 } else { 0 }),
            _ => None,
        }
    }

    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Variant::Float(f) => Some(*f),
            Variant::Int(n) => Some(*n as f64),
            _ => None,
        }
    }

    pub fn as_f32(&self) -> Option<f32> {
        self.as_f64().map(|v| v as f32)
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Variant::String(s) | Variant::StringName(s) | Variant::NodePath(s) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn as_vec3(&self) -> Option<[f32; 3]> {
        match self {
            Variant::Vector3(x, y, z) => Some([*x, *y, *z]),
            Variant::Vector3i(x, y, z) => Some([*x as f32, *y as f32, *z as f32]),
            _ => None,
        }
    }

    pub fn as_color(&self) -> Option<[f32; 4]> {
        match self {
            Variant::Color(r, g, b, a) => Some([*r, *g, *b, *a]),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[Variant]> {
        match self {
            Variant::Array(v) => Some(v.as_slice()),
            _ => None,
        }
    }

    pub fn as_dict(&self) -> Option<&[(Variant, Variant)]> {
        match self {
            Variant::Dictionary(pairs) => Some(pairs.as_slice()),
            _ => None,
        }
    }

    pub fn dict_get(&self, key: &str) -> Option<&Variant> {
        let pairs = self.as_dict()?;
        pairs
            .iter()
            .find(|(k, _)| k.as_str() == Some(key))
            .map(|(_, v)| v)
    }

    pub fn as_packed_i32(&self) -> Option<Vec<i32>> {
        match self {
            Variant::PackedInt32Array(v) => Some(v.clone()),
            Variant::Array(arr) => Some(arr.iter().filter_map(|x| x.as_int().map(|n| n as i32)).collect()),
            _ => None,
        }
    }

    pub fn as_packed_f32(&self) -> Option<Vec<f32>> {
        match self {
            Variant::PackedFloat32Array(v) => Some(v.clone()),
            Variant::PackedFloat64Array(v) => Some(v.iter().map(|x| *x as f32).collect()),
            Variant::Array(arr) => Some(arr.iter().filter_map(|x| x.as_f32()).collect()),
            _ => None,
        }
    }

    pub fn as_packed_v3(&self) -> Option<Vec<[f32; 3]>> {
        match self {
            Variant::PackedVector3Array(v) => Some(v.clone()),
            Variant::Array(arr) => Some(arr.iter().filter_map(|x| x.as_vec3()).collect()),
            _ => None,
        }
    }

    pub fn to_json(&self) -> Value {
        match self {
            Variant::Nil => Value::Null,
            Variant::Bool(b) => Value::Bool(*b),
            Variant::Int(n) => {
                if n.unsigned_abs() > (1u64 << 53) - 1 {
                    json!({ "_t": "i64", "v": n.to_string() })
                } else {
                    Value::Number(Number::from(*n))
                }
            }
            Variant::Float(f) => {
                if f.is_nan() {
                    json!({ "_t": "f", "v": "NaN" })
                } else if f.is_infinite() {
                    json!({ "_t": "f", "v": if f.is_sign_positive() { "Inf" } else { "-Inf" } })
                } else {
                    Number::from_f64(*f)
                        .map(Value::Number)
                        .unwrap_or(Value::Null)
                }
            }
            Variant::String(s) => Value::String(s.clone()),
            Variant::Vector2(x, y) => json!({ "_t": "v2", "v": [*x as f64, *y as f64] }),
            Variant::Vector2i(x, y) => json!({ "_t": "v2i", "v": [*x, *y] }),
            Variant::Rect2(x, y, w, h) => {
                json!({ "_t": "rect2", "v": [*x as f64, *y as f64, *w as f64, *h as f64] })
            }
            Variant::Rect2i(x, y, w, h) => json!({ "_t": "rect2i", "v": [*x, *y, *w, *h] }),
            Variant::Vector3(x, y, z) => {
                json!({ "_t": "v3", "v": [*x as f64, *y as f64, *z as f64] })
            }
            Variant::Vector3i(x, y, z) => json!({ "_t": "v3i", "v": [*x, *y, *z] }),
            Variant::Transform2D(m) => json!({
                "_t": "xform2d",
                "v": [[m[0] as f64, m[1] as f64], [m[2] as f64, m[3] as f64], [m[4] as f64, m[5] as f64]]
            }),
            Variant::Vector4(x, y, z, w) => {
                json!({ "_t": "v4", "v": [*x as f64, *y as f64, *z as f64, *w as f64] })
            }
            Variant::Vector4i(x, y, z, w) => json!({ "_t": "v4i", "v": [*x, *y, *z, *w] }),
            Variant::Plane(a, b, c, d) => {
                json!({ "_t": "plane", "v": [*a as f64, *b as f64, *c as f64, *d as f64] })
            }
            Variant::Quaternion(x, y, z, w) => {
                json!({ "_t": "quat", "v": [*x as f64, *y as f64, *z as f64, *w as f64] })
            }
            Variant::Aabb(pos, size) => json!({
                "_t": "aabb",
                "v": [
                    [pos[0] as f64, pos[1] as f64, pos[2] as f64],
                    [size[0] as f64, size[1] as f64, size[2] as f64]
                ]
            }),
            Variant::Basis(cols) => json!({
                "_t": "basis",
                "v": [
                    [cols[0][0] as f64, cols[0][1] as f64, cols[0][2] as f64],
                    [cols[1][0] as f64, cols[1][1] as f64, cols[1][2] as f64],
                    [cols[2][0] as f64, cols[2][1] as f64, cols[2][2] as f64]
                ]
            }),
            Variant::Transform3D { basis, origin } => json!({
                "_t": "xform3d",
                "v": [
                    [basis[0][0] as f64, basis[0][1] as f64, basis[0][2] as f64],
                    [basis[1][0] as f64, basis[1][1] as f64, basis[1][2] as f64],
                    [basis[2][0] as f64, basis[2][1] as f64, basis[2][2] as f64],
                    [origin[0] as f64, origin[1] as f64, origin[2] as f64]
                ]
            }),
            Variant::Projection(m) => {
                let cols: Vec<Vec<f64>> = (0..4)
                    .map(|c| (0..4).map(|r| m[c * 4 + r] as f64).collect())
                    .collect();
                json!({ "_t": "proj", "v": cols })
            }
            Variant::Color(r, g, b, a) => {
                json!({ "_t": "color", "v": [*r as f64, *g as f64, *b as f64, *a as f64] })
            }
            Variant::StringName(s) => json!({ "_t": "sn", "v": s }),
            Variant::NodePath(s) => json!({ "_t": "np", "v": s }),
            Variant::Dictionary(pairs) => {
                let all_plain_strings = pairs
                    .iter()
                    .all(|(k, _)| matches!(k, Variant::String(s) if s != "_t"));
                if all_plain_strings {
                    let mut map = Map::new();
                    for (k, v) in pairs {
                        if let Variant::String(ks) = k {
                            map.insert(ks.clone(), v.to_json());
                        }
                    }
                    Value::Object(map)
                } else {
                    let arr: Vec<Value> = pairs
                        .iter()
                        .map(|(k, v)| Value::Array(vec![k.to_json(), v.to_json()]))
                        .collect();
                    json!({ "_t": "dict", "v": arr })
                }
            }
            Variant::Array(items) => Value::Array(items.iter().map(|v| v.to_json()).collect()),
            Variant::PackedByteArray(bytes) => {
                let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
                json!({ "_t": "bytes", "v": b64 })
            }
            Variant::PackedInt32Array(v) => json!({ "_t": "pi32", "v": v }),
            Variant::PackedInt64Array(v) => json!({ "_t": "pi64", "v": v }),
            Variant::PackedFloat32Array(v) => {
                let vals: Vec<f64> = v.iter().map(|x| *x as f64).collect();
                json!({ "_t": "pf32", "v": vals })
            }
            Variant::PackedFloat64Array(v) => json!({ "_t": "pf64", "v": v }),
            Variant::PackedStringArray(v) => json!({ "_t": "pstr", "v": v }),
            Variant::PackedVector2Array(v) => {
                let vals: Vec<[f64; 2]> = v.iter().map(|p| [p[0] as f64, p[1] as f64]).collect();
                json!({ "_t": "pv2", "v": vals })
            }
            Variant::PackedVector3Array(v) => {
                let vals: Vec<[f64; 3]> = v
                    .iter()
                    .map(|p| [p[0] as f64, p[1] as f64, p[2] as f64])
                    .collect();
                json!({ "_t": "pv3", "v": vals })
            }
            Variant::PackedColorArray(v) => {
                let vals: Vec<[f64; 4]> = v
                    .iter()
                    .map(|p| [p[0] as f64, p[1] as f64, p[2] as f64, p[3] as f64])
                    .collect();
                json!({ "_t": "pcol", "v": vals })
            }
            Variant::PackedVector4Array(v) => {
                let vals: Vec<[f64; 4]> = v
                    .iter()
                    .map(|p| [p[0] as f64, p[1] as f64, p[2] as f64, p[3] as f64])
                    .collect();
                json!({ "_t": "pv4", "v": vals })
            }
        }
    }

    pub fn from_json(value: &Value) -> Result<Variant> {
        match value {
            Value::Null => Ok(Variant::Nil),
            Value::Bool(b) => Ok(Variant::Bool(*b)),
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    Ok(Variant::Int(i))
                } else if let Some(u) = n.as_u64() {
                    Ok(Variant::Int(u as i64))
                } else if let Some(f) = n.as_f64() {
                    Ok(Variant::Float(f))
                } else {
                    bail!("Invalid JSON number")
                }
            }
            Value::String(s) => Ok(Variant::String(s.clone())),
            Value::Array(arr) => {
                let mut out = Vec::with_capacity(arr.len());
                for item in arr {
                    out.push(Variant::from_json(item)?);
                }
                Ok(Variant::Array(out))
            }
            Value::Object(map) => {
                if map.len() == 2 {
                    if let (Some(Value::String(tag)), Some(payload)) =
                        (map.get("_t"), map.get("v"))
                    {
                        return decode_tagged_json(tag, payload);
                    }
                }
                let mut pairs = Vec::with_capacity(map.len());
                for (k, v) in map {
                    pairs.push((Variant::String(k.clone()), Variant::from_json(v)?));
                }
                Ok(Variant::Dictionary(pairs))
            }
        }
    }

    pub fn encode_bin(&self, out: &mut Vec<u8>) {
        match self {
            Variant::Nil => {
                write_u32(out, TYPE_NIL as u32);
            }
            Variant::Bool(b) => {
                write_u32(out, TYPE_BOOL as u32);
                write_u32(out, if *b { 1 } else { 0 });
            }
            Variant::Int(n) => {
                if *n >= i32::MIN as i64 && *n <= i32::MAX as i64 {
                    write_u32(out, TYPE_INT as u32);
                    write_i32(out, *n as i32);
                } else {
                    write_u32(out, (TYPE_INT as u32) | FLAG_64);
                    write_i64(out, *n);
                }
            }
            Variant::Float(f) => {
                let f32_val = *f as f32;
                let exact_f32 = (f32_val as f64) == *f || (f.is_nan() && f32_val.is_nan());
                if exact_f32 {
                    write_u32(out, TYPE_FLOAT as u32);
                    write_f32(out, f32_val);
                } else {
                    write_u32(out, (TYPE_FLOAT as u32) | FLAG_64);
                    write_f64(out, *f);
                }
            }
            Variant::String(s) => {
                write_u32(out, TYPE_STRING as u32);
                write_str4(out, s);
            }
            Variant::Vector2(x, y) => {
                write_u32(out, TYPE_VECTOR2 as u32);
                write_f32(out, *x);
                write_f32(out, *y);
            }
            Variant::Vector2i(x, y) => {
                write_u32(out, TYPE_VECTOR2I as u32);
                write_i32(out, *x);
                write_i32(out, *y);
            }
            Variant::Rect2(x, y, w, h) => {
                write_u32(out, TYPE_RECT2 as u32);
                write_f32(out, *x);
                write_f32(out, *y);
                write_f32(out, *w);
                write_f32(out, *h);
            }
            Variant::Rect2i(x, y, w, h) => {
                write_u32(out, TYPE_RECT2I as u32);
                write_i32(out, *x);
                write_i32(out, *y);
                write_i32(out, *w);
                write_i32(out, *h);
            }
            Variant::Vector3(x, y, z) => {
                write_u32(out, TYPE_VECTOR3 as u32);
                write_f32(out, *x);
                write_f32(out, *y);
                write_f32(out, *z);
            }
            Variant::Vector3i(x, y, z) => {
                write_u32(out, TYPE_VECTOR3I as u32);
                write_i32(out, *x);
                write_i32(out, *y);
                write_i32(out, *z);
            }
            Variant::Transform2D(m) => {
                write_u32(out, TYPE_TRANSFORM2D as u32);
                for v in m {
                    write_f32(out, *v);
                }
            }
            Variant::Vector4(x, y, z, w) => {
                write_u32(out, TYPE_VECTOR4 as u32);
                write_f32(out, *x);
                write_f32(out, *y);
                write_f32(out, *z);
                write_f32(out, *w);
            }
            Variant::Vector4i(x, y, z, w) => {
                write_u32(out, TYPE_VECTOR4I as u32);
                write_i32(out, *x);
                write_i32(out, *y);
                write_i32(out, *z);
                write_i32(out, *w);
            }
            Variant::Plane(a, b, c, d) => {
                write_u32(out, TYPE_PLANE as u32);
                write_f32(out, *a);
                write_f32(out, *b);
                write_f32(out, *c);
                write_f32(out, *d);
            }
            Variant::Quaternion(x, y, z, w) => {
                write_u32(out, TYPE_QUATERNION as u32);
                write_f32(out, *x);
                write_f32(out, *y);
                write_f32(out, *z);
                write_f32(out, *w);
            }
            Variant::Aabb(pos, size) => {
                write_u32(out, TYPE_AABB as u32);
                for v in pos {
                    write_f32(out, *v);
                }
                for v in size {
                    write_f32(out, *v);
                }
            }
            Variant::Basis(cols) => {
                write_u32(out, TYPE_BASIS as u32);
                // Binary BASIS is row-major: x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z
                for row in 0..3 {
                    for col in 0..3 {
                        write_f32(out, cols[col][row]);
                    }
                }
            }
            Variant::Transform3D { basis, origin } => {
                write_u32(out, TYPE_TRANSFORM3D as u32);
                for row in 0..3 {
                    for col in 0..3 {
                        write_f32(out, basis[col][row]);
                    }
                }
                for v in origin {
                    write_f32(out, *v);
                }
            }
            Variant::Projection(m) => {
                write_u32(out, TYPE_PROJECTION as u32);
                for v in m {
                    write_f32(out, *v);
                }
            }
            Variant::Color(r, g, b, a) => {
                write_u32(out, TYPE_COLOR as u32);
                write_f32(out, *r);
                write_f32(out, *g);
                write_f32(out, *b);
                write_f32(out, *a);
            }
            Variant::StringName(s) => {
                write_u32(out, TYPE_STRING_NAME as u32);
                write_str4(out, s);
            }
            Variant::NodePath(path) => {
                write_u32(out, TYPE_NODE_PATH as u32);
                let (absolute, rest) = match path.strip_prefix('/') {
                    Some(r) => (true, r),
                    None => (false, path.as_str()),
                };
                let (names_part, subnames_part) = match rest.split_once(':') {
                    Some((n, s)) => (n, Some(s)),
                    None => (rest, None),
                };
                let names: Vec<&str> = if names_part.is_empty() {
                    Vec::new()
                } else {
                    names_part.split('/').filter(|s| !s.is_empty()).collect()
                };
                let subnames: Vec<&str> = match subnames_part {
                    Some(sp) if !sp.is_empty() => sp.split(':').filter(|s| !s.is_empty()).collect(),
                    _ => Vec::new(),
                };
                write_u32(out, (names.len() as u32) | 0x8000_0000);
                write_u32(out, subnames.len() as u32);
                write_u32(out, if absolute { 1 } else { 0 });
                for n in names {
                    write_str4(out, n);
                }
                for s in subnames {
                    write_str4(out, s);
                }
            }
            Variant::Dictionary(pairs) => {
                write_u32(out, TYPE_DICTIONARY as u32);
                write_u32(out, pairs.len() as u32);
                for (k, v) in pairs {
                    k.encode_bin(out);
                    v.encode_bin(out);
                }
            }
            Variant::Array(items) => {
                write_u32(out, TYPE_ARRAY as u32);
                write_u32(out, items.len() as u32);
                for item in items {
                    item.encode_bin(out);
                }
            }
            Variant::PackedByteArray(bytes) => {
                write_u32(out, TYPE_PACKED_BYTE_ARRAY as u32);
                write_u32(out, bytes.len() as u32);
                out.extend_from_slice(bytes);
                let pad = (4 - (bytes.len() % 4)) % 4;
                out.resize(out.len() + pad, 0);
            }
            Variant::PackedInt32Array(v) => {
                write_u32(out, TYPE_PACKED_INT32_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for x in v {
                    write_i32(out, *x);
                }
            }
            Variant::PackedInt64Array(v) => {
                write_u32(out, TYPE_PACKED_INT64_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for x in v {
                    write_i64(out, *x);
                }
            }
            Variant::PackedFloat32Array(v) => {
                write_u32(out, TYPE_PACKED_FLOAT32_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for x in v {
                    write_f32(out, *x);
                }
            }
            Variant::PackedFloat64Array(v) => {
                write_u32(out, TYPE_PACKED_FLOAT64_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for x in v {
                    write_f64(out, *x);
                }
            }
            Variant::PackedStringArray(v) => {
                write_u32(out, TYPE_PACKED_STRING_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for s in v {
                    write_str4(out, s);
                }
            }
            Variant::PackedVector2Array(v) => {
                write_u32(out, TYPE_PACKED_VECTOR2_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for p in v {
                    write_f32(out, p[0]);
                    write_f32(out, p[1]);
                }
            }
            Variant::PackedVector3Array(v) => {
                write_u32(out, TYPE_PACKED_VECTOR3_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for p in v {
                    write_f32(out, p[0]);
                    write_f32(out, p[1]);
                    write_f32(out, p[2]);
                }
            }
            Variant::PackedColorArray(v) => {
                write_u32(out, TYPE_PACKED_COLOR_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for c in v {
                    write_f32(out, c[0]);
                    write_f32(out, c[1]);
                    write_f32(out, c[2]);
                    write_f32(out, c[3]);
                }
            }
            Variant::PackedVector4Array(v) => {
                write_u32(out, TYPE_PACKED_VECTOR4_ARRAY as u32);
                write_u32(out, v.len() as u32);
                for p in v {
                    write_f32(out, p[0]);
                    write_f32(out, p[1]);
                    write_f32(out, p[2]);
                    write_f32(out, p[3]);
                }
            }
        }
    }

    pub fn decode_bin(data: &[u8], offset: &mut usize) -> Result<Variant> {
        let header = read_u32(data, offset)?;
        let ty = (header & 0xFF) as u8;
        let is_64 = (header & FLAG_64) != 0;

        match ty {
            TYPE_NIL => Ok(Variant::Nil),
            TYPE_BOOL => {
                let v = read_u32(data, offset)?;
                Ok(Variant::Bool(v != 0))
            }
            TYPE_INT => {
                if is_64 {
                    Ok(Variant::Int(read_i64(data, offset)?))
                } else {
                    Ok(Variant::Int(read_i32(data, offset)? as i64))
                }
            }
            TYPE_FLOAT => {
                if is_64 {
                    Ok(Variant::Float(read_f64(data, offset)?))
                } else {
                    Ok(Variant::Float(read_f32(data, offset)? as f64))
                }
            }
            TYPE_STRING => Ok(Variant::String(read_str4(data, offset)?)),
            TYPE_STRING_NAME => Ok(Variant::StringName(read_str4(data, offset)?)),
            TYPE_VECTOR2 => {
                let x = read_real(data, offset, is_64)?;
                let y = read_real(data, offset, is_64)?;
                Ok(Variant::Vector2(x, y))
            }
            TYPE_VECTOR2I => {
                let x = read_i32(data, offset)?;
                let y = read_i32(data, offset)?;
                Ok(Variant::Vector2i(x, y))
            }
            TYPE_RECT2 => {
                let x = read_real(data, offset, is_64)?;
                let y = read_real(data, offset, is_64)?;
                let w = read_real(data, offset, is_64)?;
                let h = read_real(data, offset, is_64)?;
                Ok(Variant::Rect2(x, y, w, h))
            }
            TYPE_RECT2I => {
                let x = read_i32(data, offset)?;
                let y = read_i32(data, offset)?;
                let w = read_i32(data, offset)?;
                let h = read_i32(data, offset)?;
                Ok(Variant::Rect2i(x, y, w, h))
            }
            TYPE_VECTOR3 => {
                let x = read_real(data, offset, is_64)?;
                let y = read_real(data, offset, is_64)?;
                let z = read_real(data, offset, is_64)?;
                Ok(Variant::Vector3(x, y, z))
            }
            TYPE_VECTOR3I => {
                let x = read_i32(data, offset)?;
                let y = read_i32(data, offset)?;
                let z = read_i32(data, offset)?;
                Ok(Variant::Vector3i(x, y, z))
            }
            TYPE_TRANSFORM2D => {
                let mut m = [0.0f32; 6];
                for slot in &mut m {
                    *slot = read_real(data, offset, is_64)?;
                }
                Ok(Variant::Transform2D(m))
            }
            TYPE_VECTOR4 => {
                let x = read_real(data, offset, is_64)?;
                let y = read_real(data, offset, is_64)?;
                let z = read_real(data, offset, is_64)?;
                let w = read_real(data, offset, is_64)?;
                Ok(Variant::Vector4(x, y, z, w))
            }
            TYPE_VECTOR4I => {
                let x = read_i32(data, offset)?;
                let y = read_i32(data, offset)?;
                let z = read_i32(data, offset)?;
                let w = read_i32(data, offset)?;
                Ok(Variant::Vector4i(x, y, z, w))
            }
            TYPE_PLANE => {
                let a = read_real(data, offset, is_64)?;
                let b = read_real(data, offset, is_64)?;
                let c = read_real(data, offset, is_64)?;
                let d = read_real(data, offset, is_64)?;
                Ok(Variant::Plane(a, b, c, d))
            }
            TYPE_QUATERNION => {
                let x = read_real(data, offset, is_64)?;
                let y = read_real(data, offset, is_64)?;
                let z = read_real(data, offset, is_64)?;
                let w = read_real(data, offset, is_64)?;
                Ok(Variant::Quaternion(x, y, z, w))
            }
            TYPE_AABB => {
                let pos = [
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                ];
                let size = [
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                ];
                Ok(Variant::Aabb(pos, size))
            }
            TYPE_BASIS => {
                let mut cols = [[0.0f32; 3]; 3];
                for row in 0..3 {
                    for col in 0..3 {
                        cols[col][row] = read_real(data, offset, is_64)?;
                    }
                }
                Ok(Variant::Basis(cols))
            }
            TYPE_TRANSFORM3D => {
                let mut basis = [[0.0f32; 3]; 3];
                for row in 0..3 {
                    for col in 0..3 {
                        basis[col][row] = read_real(data, offset, is_64)?;
                    }
                }
                let origin = [
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                    read_real(data, offset, is_64)?,
                ];
                Ok(Variant::Transform3D { basis, origin })
            }
            TYPE_PROJECTION => {
                let mut m = [0.0f32; 16];
                for slot in &mut m {
                    *slot = read_real(data, offset, is_64)?;
                }
                Ok(Variant::Projection(m))
            }
            TYPE_COLOR => {
                let r = read_f32(data, offset)?;
                let g = read_f32(data, offset)?;
                let b = read_f32(data, offset)?;
                let a = read_f32(data, offset)?;
                Ok(Variant::Color(r, g, b, a))
            }
            TYPE_NODE_PATH => {
                let raw_name_count = read_u32(data, offset)?;
                if (raw_name_count & 0x8000_0000) == 0 {
                    // Legacy single-string format
                    let len = raw_name_count as usize;
                    let s = read_raw_str_padded(data, offset, len)?;
                    Ok(Variant::NodePath(s))
                } else {
                    let name_count = (raw_name_count & 0x7FFF_FFFF) as usize;
                    let subname_count = read_u32(data, offset)? as usize;
                    let flags = read_u32(data, offset)?;
                    let absolute = (flags & 1) != 0;
                    let mut names = Vec::with_capacity(name_count);
                    for _ in 0..name_count {
                        names.push(read_str4(data, offset)?);
                    }
                    let mut subnames = Vec::with_capacity(subname_count);
                    for _ in 0..subname_count {
                        subnames.push(read_str4(data, offset)?);
                    }
                    let mut path = String::new();
                    if absolute {
                        path.push('/');
                    }
                    path.push_str(&names.join("/"));
                    for sub in subnames {
                        path.push(':');
                        path.push_str(&sub);
                    }
                    Ok(Variant::NodePath(path))
                }
            }
            TYPE_DICTIONARY => {
                let key_kind = (header >> 16) & 0x3;
                let val_kind = (header >> 18) & 0x3;
                skip_container_type(data, offset, key_kind)?;
                skip_container_type(data, offset, val_kind)?;
                let count = (read_u32(data, offset)? & 0x7FFF_FFFF) as usize;
                let mut pairs = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    let k = Variant::decode_bin(data, offset)?;
                    let v = Variant::decode_bin(data, offset)?;
                    pairs.push((k, v));
                }
                Ok(Variant::Dictionary(pairs))
            }
            TYPE_ARRAY => {
                let elem_kind = (header >> 16) & 0x3;
                skip_container_type(data, offset, elem_kind)?;
                let count = (read_u32(data, offset)? & 0x7FFF_FFFF) as usize;
                let mut items = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    items.push(Variant::decode_bin(data, offset)?);
                }
                Ok(Variant::Array(items))
            }
            TYPE_PACKED_BYTE_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let bytes = read_bytes(data, offset, count)?.to_vec();
                let pad = (4 - (count % 4)) % 4;
                let _ = read_bytes(data, offset, pad)?;
                Ok(Variant::PackedByteArray(bytes))
            }
            TYPE_PACKED_INT32_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push(read_i32(data, offset)?);
                }
                Ok(Variant::PackedInt32Array(out))
            }
            TYPE_PACKED_INT64_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push(read_i64(data, offset)?);
                }
                Ok(Variant::PackedInt64Array(out))
            }
            TYPE_PACKED_FLOAT32_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push(read_f32(data, offset)?);
                }
                Ok(Variant::PackedFloat32Array(out))
            }
            TYPE_PACKED_FLOAT64_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push(read_f64(data, offset)?);
                }
                Ok(Variant::PackedFloat64Array(out))
            }
            TYPE_PACKED_STRING_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push(read_str4(data, offset)?);
                }
                Ok(Variant::PackedStringArray(out))
            }
            TYPE_PACKED_VECTOR2_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push([read_f32(data, offset)?, read_f32(data, offset)?]);
                }
                Ok(Variant::PackedVector2Array(out))
            }
            TYPE_PACKED_VECTOR3_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push([
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                    ]);
                }
                Ok(Variant::PackedVector3Array(out))
            }
            TYPE_PACKED_COLOR_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push([
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                    ]);
                }
                Ok(Variant::PackedColorArray(out))
            }
            TYPE_PACKED_VECTOR4_ARRAY => {
                let count = read_u32(data, offset)? as usize;
                let mut out = Vec::with_capacity(count.min(4096));
                for _ in 0..count {
                    out.push([
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                        read_f32(data, offset)?,
                    ]);
                }
                Ok(Variant::PackedVector4Array(out))
            }
            23..=26 => Ok(Variant::Nil),
            other => bail!("Unsupported binary Variant type id {}", other),
        }
    }
}

fn decode_tagged_json(tag: &str, v: &Value) -> Result<Variant> {
    match tag {
        "i" => {
            let n = v
                .as_i64()
                .or_else(|| v.as_f64().map(|f| f as i64))
                .ok_or_else(|| anyhow!("Invalid tagged int"))?;
            Ok(Variant::Int(n))
        }
        "i64" => {
            if let Some(s) = v.as_str() {
                Ok(Variant::Int(s.parse::<i64>().context("Invalid i64 string")?))
            } else if let Some(n) = v.as_i64() {
                Ok(Variant::Int(n))
            } else {
                bail!("Invalid i64 payload")
            }
        }
        "f" => {
            if let Some(s) = v.as_str() {
                match s {
                    "NaN" => Ok(Variant::Float(f64::NAN)),
                    "Inf" => Ok(Variant::Float(f64::INFINITY)),
                    "-Inf" => Ok(Variant::Float(f64::NEG_INFINITY)),
                    _ => Ok(Variant::Float(s.parse::<f64>()?)),
                }
            } else if let Some(f) = v.as_f64() {
                Ok(Variant::Float(f))
            } else {
                bail!("Invalid tagged float")
            }
        }
        "v2" => {
            let a = json_f32_slice(v, 2)?;
            Ok(Variant::Vector2(a[0], a[1]))
        }
        "v2i" => {
            let a = json_i32_slice(v, 2)?;
            Ok(Variant::Vector2i(a[0], a[1]))
        }
        "rect2" => {
            let a = json_f32_slice(v, 4)?;
            Ok(Variant::Rect2(a[0], a[1], a[2], a[3]))
        }
        "rect2i" => {
            let a = json_i32_slice(v, 4)?;
            Ok(Variant::Rect2i(a[0], a[1], a[2], a[3]))
        }
        "v3" => {
            let a = json_f32_slice(v, 3)?;
            Ok(Variant::Vector3(a[0], a[1], a[2]))
        }
        "v3i" => {
            let a = json_i32_slice(v, 3)?;
            Ok(Variant::Vector3i(a[0], a[1], a[2]))
        }
        "xform2d" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected xform2d array"))?;
            if arr.len() != 3 {
                bail!("Expected 3 columns in xform2d");
            }
            let c0 = json_f32_slice(&arr[0], 2)?;
            let c1 = json_f32_slice(&arr[1], 2)?;
            let c2 = json_f32_slice(&arr[2], 2)?;
            Ok(Variant::Transform2D([c0[0], c0[1], c1[0], c1[1], c2[0], c2[1]]))
        }
        "v4" => {
            let a = json_f32_slice(v, 4)?;
            Ok(Variant::Vector4(a[0], a[1], a[2], a[3]))
        }
        "v4i" => {
            let a = json_i32_slice(v, 4)?;
            Ok(Variant::Vector4i(a[0], a[1], a[2], a[3]))
        }
        "plane" => {
            let a = json_f32_slice(v, 4)?;
            Ok(Variant::Plane(a[0], a[1], a[2], a[3]))
        }
        "quat" => {
            let a = json_f32_slice(v, 4)?;
            Ok(Variant::Quaternion(a[0], a[1], a[2], a[3]))
        }
        "aabb" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected aabb array"))?;
            if arr.len() != 2 {
                bail!("Expected [pos, size] in aabb");
            }
            let p = json_f32_slice(&arr[0], 3)?;
            let s = json_f32_slice(&arr[1], 3)?;
            Ok(Variant::Aabb([p[0], p[1], p[2]], [s[0], s[1], s[2]]))
        }
        "basis" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected basis array"))?;
            if arr.len() != 3 {
                bail!("Expected 3 columns in basis");
            }
            let c0 = json_f32_slice(&arr[0], 3)?;
            let c1 = json_f32_slice(&arr[1], 3)?;
            let c2 = json_f32_slice(&arr[2], 3)?;
            Ok(Variant::Basis([
                [c0[0], c0[1], c0[2]],
                [c1[0], c1[1], c1[2]],
                [c2[0], c2[1], c2[2]],
            ]))
        }
        "xform3d" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected xform3d array"))?;
            if arr.len() != 4 {
                bail!("Expected 4 vectors in xform3d");
            }
            let c0 = json_f32_slice(&arr[0], 3)?;
            let c1 = json_f32_slice(&arr[1], 3)?;
            let c2 = json_f32_slice(&arr[2], 3)?;
            let o = json_f32_slice(&arr[3], 3)?;
            Ok(Variant::Transform3D {
                basis: [
                    [c0[0], c0[1], c0[2]],
                    [c1[0], c1[1], c1[2]],
                    [c2[0], c2[1], c2[2]],
                ],
                origin: [o[0], o[1], o[2]],
            })
        }
        "proj" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected proj array"))?;
            if arr.len() != 4 {
                bail!("Expected 4 columns in proj");
            }
            let mut m = [0.0f32; 16];
            for c in 0..4 {
                let col = json_f32_slice(&arr[c], 4)?;
                for r in 0..4 {
                    m[c * 4 + r] = col[r];
                }
            }
            Ok(Variant::Projection(m))
        }
        "color" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected color array"))?;
            if arr.len() < 3 {
                bail!("Expected 3 or 4 floats in color");
            }
            let r = arr[0].as_f64().unwrap_or(0.0) as f32;
            let g = arr[1].as_f64().unwrap_or(0.0) as f32;
            let b = arr[2].as_f64().unwrap_or(0.0) as f32;
            let a = arr.get(3).and_then(|x| x.as_f64()).unwrap_or(1.0) as f32;
            Ok(Variant::Color(r, g, b, a))
        }
        "sn" => Ok(Variant::StringName(
            v.as_str().ok_or_else(|| anyhow!("Expected sn string"))?.to_string(),
        )),
        "np" => Ok(Variant::NodePath(
            v.as_str().ok_or_else(|| anyhow!("Expected np string"))?.to_string(),
        )),
        "dict" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected dict pair array"))?;
            let mut pairs = Vec::with_capacity(arr.len());
            for pair in arr {
                let p = pair.as_array().ok_or_else(|| anyhow!("Expected [k,v] pair"))?;
                if p.len() != 2 {
                    bail!("Expected length-2 pair in tagged dict");
                }
                pairs.push((Variant::from_json(&p[0])?, Variant::from_json(&p[1])?));
            }
            Ok(Variant::Dictionary(pairs))
        }
        "bytes" => {
            let s = v.as_str().ok_or_else(|| anyhow!("Expected base64 string"))?;
            let bytes = base64::engine::general_purpose::STANDARD
                .decode(s)
                .context("Invalid base64 in bytes variant")?;
            Ok(Variant::PackedByteArray(bytes))
        }
        "pi32" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pi32 array"))?;
            let out = arr
                .iter()
                .map(|x| x.as_i64().or_else(|| x.as_f64().map(|f| f as i64)).unwrap_or(0) as i32)
                .collect();
            Ok(Variant::PackedInt32Array(out))
        }
        "pi64" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pi64 array"))?;
            let out = arr
                .iter()
                .map(|x| x.as_i64().or_else(|| x.as_f64().map(|f| f as i64)).unwrap_or(0))
                .collect();
            Ok(Variant::PackedInt64Array(out))
        }
        "pf32" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pf32 array"))?;
            let out = arr.iter().map(|x| x.as_f64().unwrap_or(0.0) as f32).collect();
            Ok(Variant::PackedFloat32Array(out))
        }
        "pf64" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pf64 array"))?;
            let out = arr.iter().map(|x| x.as_f64().unwrap_or(0.0)).collect();
            Ok(Variant::PackedFloat64Array(out))
        }
        "pstr" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pstr array"))?;
            let out = arr
                .iter()
                .map(|x| x.as_str().unwrap_or_default().to_string())
                .collect();
            Ok(Variant::PackedStringArray(out))
        }
        "pv2" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pv2 array"))?;
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let p = json_f32_slice(item, 2)?;
                out.push([p[0], p[1]]);
            }
            Ok(Variant::PackedVector2Array(out))
        }
        "pv3" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pv3 array"))?;
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let p = json_f32_slice(item, 3)?;
                out.push([p[0], p[1], p[2]]);
            }
            Ok(Variant::PackedVector3Array(out))
        }
        "pcol" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pcol array"))?;
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let p = json_f32_slice(item, 4)?;
                out.push([p[0], p[1], p[2], p[3]]);
            }
            Ok(Variant::PackedColorArray(out))
        }
        "pv4" => {
            let arr = v.as_array().ok_or_else(|| anyhow!("Expected pv4 array"))?;
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let p = json_f32_slice(item, 4)?;
                out.push([p[0], p[1], p[2], p[3]]);
            }
            Ok(Variant::PackedVector4Array(out))
        }
        other => bail!("Unknown tagged JSON Variant type '{}'", other),
    }
}

fn json_f32_slice(v: &Value, expected: usize) -> Result<Vec<f32>> {
    let arr = v.as_array().ok_or_else(|| anyhow!("Expected JSON float array"))?;
    if arr.len() != expected {
        bail!("Expected {} floats, got {}", expected, arr.len());
    }
    let mut out = Vec::with_capacity(expected);
    for item in arr {
        out.push(
            item.as_f64()
                .ok_or_else(|| anyhow!("Expected number in float array"))? as f32,
        );
    }
    Ok(out)
}

fn json_i32_slice(v: &Value, expected: usize) -> Result<Vec<i32>> {
    let arr = v.as_array().ok_or_else(|| anyhow!("Expected JSON int array"))?;
    if arr.len() != expected {
        bail!("Expected {} ints, got {}", expected, arr.len());
    }
    let mut out = Vec::with_capacity(expected);
    for item in arr {
        let n = item
            .as_i64()
            .or_else(|| item.as_f64().map(|f| f as i64))
            .ok_or_else(|| anyhow!("Expected int in int array"))?;
        out.push(n as i32);
    }
    Ok(out)
}

fn write_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_i32(out: &mut Vec<u8>, v: i32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_i64(out: &mut Vec<u8>, v: i64) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_f32(out: &mut Vec<u8>, v: f32) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_f64(out: &mut Vec<u8>, v: f64) {
    out.extend_from_slice(&v.to_le_bytes());
}

fn write_str4(out: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    write_u32(out, bytes.len() as u32);
    out.extend_from_slice(bytes);
    let pad = (4 - (bytes.len() % 4)) % 4;
    out.resize(out.len() + pad, 0);
}

fn read_bytes<'a>(data: &'a [u8], offset: &mut usize, len: usize) -> Result<&'a [u8]> {
    if offset.checked_add(len).map(|e| e > data.len()).unwrap_or(true) {
        bail!("Unexpected EOF reading {} bytes at offset {}", len, *offset);
    }
    let slice = &data[*offset..*offset + len];
    *offset += len;
    Ok(slice)
}

fn read_u32(data: &[u8], offset: &mut usize) -> Result<u32> {
    let b = read_bytes(data, offset, 4)?;
    Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn read_i32(data: &[u8], offset: &mut usize) -> Result<i32> {
    let b = read_bytes(data, offset, 4)?;
    Ok(i32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn read_i64(data: &[u8], offset: &mut usize) -> Result<i64> {
    let b = read_bytes(data, offset, 8)?;
    Ok(i64::from_le_bytes([
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
    ]))
}

fn read_f32(data: &[u8], offset: &mut usize) -> Result<f32> {
    let b = read_bytes(data, offset, 4)?;
    Ok(f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
}

fn read_f64(data: &[u8], offset: &mut usize) -> Result<f64> {
    let b = read_bytes(data, offset, 8)?;
    Ok(f64::from_le_bytes([
        b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
    ]))
}

fn read_real(data: &[u8], offset: &mut usize, is_64: bool) -> Result<f32> {
    if is_64 {
        Ok(read_f64(data, offset)? as f32)
    } else {
        read_f32(data, offset)
    }
}

fn read_str4(data: &[u8], offset: &mut usize) -> Result<String> {
    let len = read_u32(data, offset)? as usize;
    read_raw_str_padded(data, offset, len)
}

fn read_raw_str_padded(data: &[u8], offset: &mut usize, len: usize) -> Result<String> {
    let b = read_bytes(data, offset, len)?;
    let s = std::str::from_utf8(b)
        .context("Invalid UTF-8 in binary Variant string")?
        .to_string();
    let pad = (4 - (len % 4)) % 4;
    let _ = read_bytes(data, offset, pad)?;
    Ok(s)
}

fn skip_container_type(data: &[u8], offset: &mut usize, kind: u32) -> Result<()> {
    match kind {
        0 => Ok(()),
        1 => {
            let _builtin = read_u32(data, offset)?;
            Ok(())
        }
        2 | 3 => {
            let _name_or_script = read_str4(data, offset)?;
            Ok(())
        }
        other => bail!("Invalid container type kind {}", other),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hex_to_bytes(hex: &str) -> Vec<u8> {
        let cleaned: String = hex.chars().filter(|c| !c.is_whitespace()).collect();
        (0..cleaned.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&cleaned[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn json_roundtrip_tagged_types() {
        let v = Variant::Dictionary(vec![
            (
                Variant::Int(234289745),
                Variant::Dictionary(vec![
                    (Variant::String("color".into()), Variant::Int(3)),
                    (Variant::String("name".into()), Variant::String("Full Bot".into())),
                    (Variant::String("ready".into()), Variant::Bool(true)),
                ]),
            ),
            (
                Variant::NodePath("/root/Main/Level/Puddles/MainW".into()),
                Variant::Vector3(1.5, 0.25, -4.0),
            ),
        ]);
        let j = v.to_json();
        assert_eq!(j["_t"], "dict");
        let back = Variant::from_json(&j).unwrap();
        assert_eq!(back, v);
    }

    #[test]
    fn json_roundtrip_color_and_nodepath() {
        let color = Variant::Color(0.4, 0.875, 0.85, 1.0);
        let back = Variant::from_json(&color.to_json()).unwrap();
        assert_eq!(back, color);

        let np = Variant::NodePath("/root/Main/Level/DeconShowers/GasStation/Interact".into());
        let np_back = Variant::from_json(&np.to_json()).unwrap();
        assert_eq!(np_back, np);
    }

    #[test]
    fn binary_float_f32_and_f64_flags() {
        // 12.0 is exact in f32 -> 8 bytes total (header + f32)
        let mut b32 = Vec::new();
        Variant::Float(12.0).encode_bin(&mut b32);
        assert_eq!(b32, hex_to_bytes("03 00 00 00 00 00 40 41"));
        let mut off = 0;
        assert_eq!(Variant::decode_bin(&b32, &mut off).unwrap(), Variant::Float(12.0));
        assert_eq!(off, b32.len());

        // 44.045620832318136 is NOT exact in f32 -> FLAG_64 + f64 (12 bytes)
        let val = 44.045620832318136_f64;
        let mut b64 = Vec::new();
        Variant::Float(val).encode_bin(&mut b64);
        assert_eq!(b64, hex_to_bytes("03 00 01 00 4e 69 47 e7 d6 05 46 40"));
        let mut off2 = 0;
        assert_eq!(Variant::decode_bin(&b64, &mut off2).unwrap(), Variant::Float(val));
        assert_eq!(off2, b64.len());
    }

    #[test]
    fn binary_typed_array_and_typed_dict_decode() {
        // spec-full.md §10 example 8: typed empty Array[String]
        let bytes = hex_to_bytes("1c 00 01 00 04 00 00 00 00 00 00 00");
        let mut off = 0;
        let v = Variant::decode_bin(&bytes, &mut off).unwrap();
        assert_eq!(v, Variant::Array(vec![]));
        assert_eq!(off, bytes.len());

        // Typed Dictionary[int, String] with 1 pair: header 1b 00 05 00 (key kind 1, val kind 1)
        let mut dict_bytes = Vec::new();
        dict_bytes.extend_from_slice(&(TYPE_DICTIONARY as u32 | (1 << 16) | (1 << 18)).to_le_bytes());
        dict_bytes.extend_from_slice(&(TYPE_INT as u32).to_le_bytes());
        dict_bytes.extend_from_slice(&(TYPE_STRING as u32).to_le_bytes());
        dict_bytes.extend_from_slice(&1u32.to_le_bytes());
        Variant::Int(42).encode_bin(&mut dict_bytes);
        Variant::String("ok".into()).encode_bin(&mut dict_bytes);
        let mut off2 = 0;
        let dv = Variant::decode_bin(&dict_bytes, &mut off2).unwrap();
        assert_eq!(
            dv,
            Variant::Dictionary(vec![(Variant::Int(42), Variant::String("ok".into()))])
        );
        assert_eq!(off2, dict_bytes.len());
    }

    #[test]
    fn binary_node_path_worked_example() {
        // spec-full.md §10 example 9
        let expected = hex_to_bytes(
            "16 00 00 00  05 00 00 80  00 00 00 00  01 00 00 00
             04 00 00 00 72 6f 6f 74   04 00 00 00 4d 61 69 6e
             05 00 00 00 4c 65 76 65 6c 00 00 00   07 00 00 00 50 75 64 64 6c 65 73 00
             05 00 00 00 4d 61 69 6e 57 00 00 00",
        );
        let np = Variant::NodePath("/root/Main/Level/Puddles/MainW".into());
        let mut encoded = Vec::new();
        np.encode_bin(&mut encoded);
        assert_eq!(encoded, expected);
        let mut off = 0;
        assert_eq!(Variant::decode_bin(&encoded, &mut off).unwrap(), np);
        assert_eq!(off, encoded.len());
    }
}
