#![allow(dead_code)]

use anyhow::{anyhow, bail, Context, Result};
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use super::variant::Variant;

pub const OPEN_PROTOCOL_VERSION: i64 = 1;
pub const GAME_PROTOCOL_VERSION: i64 = 19;
pub const MAX_CLIENT_FRAME_BYTES: usize = 65_536;
pub const MAX_SERVER_FRAME_BYTES: usize = 524_284;

pub const BIN_TAG_RPC: u8 = 0x03;
pub const BIN_TAG_RAW: u8 = 0x04;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Encoding {
    Json,
    Bin,
}

impl Encoding {
    pub fn as_str(&self) -> &'static str {
        match self {
            Encoding::Json => "json",
            Encoding::Bin => "bin",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferMode {
    Unreliable = 0,
    UnreliableOrdered = 1,
    Reliable = 2,
}

impl TransferMode {
    pub fn from_flags(flags: u8) -> Self {
        match flags & 0x03 {
            0 => TransferMode::Unreliable,
            1 => TransferMode::UnreliableOrdered,
            _ => TransferMode::Reliable,
        }
    }

    pub fn is_reliable(self) -> bool {
        matches!(self, TransferMode::Reliable)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MapInfo {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RpcMessage {
    pub node: String,
    pub method: String,
    pub args: Vec<Variant>,
    pub channel: u8,
    pub mode: TransferMode,
}

impl RpcMessage {
    pub fn reliable(node: impl Into<String>, method: impl Into<String>, args: Vec<Variant>) -> Self {
        Self {
            node: node.into(),
            method: method.into(),
            args,
            channel: 0,
            mode: TransferMode::Reliable,
        }
    }

    pub fn unreliable_ordered(
        node: impl Into<String>,
        method: impl Into<String>,
        args: Vec<Variant>,
    ) -> Self {
        Self {
            node: node.into(),
            method: method.into(),
            args,
            channel: 0,
            mode: TransferMode::UnreliableOrdered,
        }
    }

    pub fn unreliable(
        node: impl Into<String>,
        method: impl Into<String>,
        args: Vec<Variant>,
    ) -> Self {
        Self {
            node: node.into(),
            method: method.into(),
            args,
            channel: 0,
            mode: TransferMode::Unreliable,
        }
    }

    pub fn encode_json(&self) -> String {
        let args: Vec<Value> = self.args.iter().map(|a| a.to_json()).collect();
        let obj = json!({
            "t": "rpc",
            "node": self.node,
            "method": self.method,
            "args": args,
            "ch": self.channel,
            "rel": self.mode.is_reliable(),
        });
        obj.to_string()
    }

    pub fn encode_bin(&self) -> Result<Vec<u8>> {
        let node_bytes = self.node.as_bytes();
        let method_bytes = self.method.as_bytes();
        if node_bytes.len() > u16::MAX as usize {
            bail!("RPC node path too long");
        }
        if method_bytes.len() > u8::MAX as usize {
            bail!("RPC method name too long");
        }
        if self.args.len() > u8::MAX as usize {
            bail!("Too many RPC arguments: {}", self.args.len());
        }

        let mut out = Vec::with_capacity(7 + node_bytes.len() + method_bytes.len() + self.args.len() * 8);
        out.push(BIN_TAG_RPC);
        out.push((self.mode as u8) & 0x03);
        out.push(self.channel);
        out.extend_from_slice(&(node_bytes.len() as u16).to_le_bytes());
        out.extend_from_slice(node_bytes);
        out.push(method_bytes.len() as u8);
        out.extend_from_slice(method_bytes);
        out.push(self.args.len() as u8);
        for arg in &self.args {
            arg.encode_bin(&mut out);
        }
        Ok(out)
    }

    pub fn decode_bin(data: &[u8]) -> Result<Self> {
        if data.len() < 7 {
            bail!("Binary RPC frame too short ({} bytes)", data.len());
        }
        if data[0] != BIN_TAG_RPC {
            bail!("Expected RPC tag 0x03, got 0x{:02x}", data[0]);
        }
        let mode = TransferMode::from_flags(data[1]);
        let channel = data[2];
        let node_len = u16::from_le_bytes([data[3], data[4]]) as usize;
        let mut off = 5usize;
        if off + node_len + 2 > data.len() {
            bail!("Truncated binary RPC node path");
        }
        let node = std::str::from_utf8(&data[off..off + node_len])
            .context("Invalid UTF-8 in binary RPC node")?
            .to_string();
        off += node_len;

        let method_len = data[off] as usize;
        off += 1;
        if off + method_len + 1 > data.len() {
            bail!("Truncated binary RPC method name");
        }
        let method = std::str::from_utf8(&data[off..off + method_len])
            .context("Invalid UTF-8 in binary RPC method")?
            .to_string();
        off += method_len;

        let argc = data[off] as usize;
        off += 1;

        let mut args = Vec::with_capacity(argc);
        for i in 0..argc {
            let v = Variant::decode_bin(data, &mut off)
                .with_context(|| format!("Invalid binary variant arg {} in {}.{}", i, node, method))?;
            args.push(v);
        }

        Ok(Self {
            node,
            method,
            args,
            channel,
            mode,
        })
    }
}

#[derive(Debug, Clone)]
pub enum OutboundMessage {
    Hello {
        v: i64,
        tier: String,
        enc: Encoding,
        client: String,
        code: Option<String>,
    },
    Ping {
        ms: i64,
    },
    Leave,
    Rpc(RpcMessage),
}

#[derive(Debug, Clone)]
pub enum WireFrame {
    Text(String),
    Binary(Vec<u8>),
}

impl OutboundMessage {
    pub fn encode(&self, enc: Encoding) -> Result<WireFrame> {
        let frame = match self {
            OutboundMessage::Hello {
                v,
                tier,
                enc: req_enc,
                client,
                code,
            } => {
                let mut map = serde_json::Map::new();
                map.insert("t".into(), json!("hello"));
                map.insert("v".into(), json!(v));
                map.insert("tier".into(), json!(tier));
                map.insert("enc".into(), json!(req_enc.as_str()));
                map.insert("client".into(), json!(client));
                if let Some(c) = code {
                    if !c.is_empty() {
                        map.insert("code".into(), json!(c));
                    }
                }
                WireFrame::Text(Value::Object(map).to_string())
            }
            OutboundMessage::Ping { ms } => {
                WireFrame::Text(json!({ "t": "ping", "ms": ms }).to_string())
            }
            OutboundMessage::Leave => WireFrame::Text(json!({ "t": "leave" }).to_string()),
            OutboundMessage::Rpc(rpc) => match enc {
                Encoding::Json => WireFrame::Text(rpc.encode_json()),
                Encoding::Bin => WireFrame::Binary(rpc.encode_bin()?),
            },
        };

        let len = match &frame {
            WireFrame::Text(s) => s.len(),
            WireFrame::Binary(b) => b.len(),
        };
        if len == 0 || len > MAX_CLIENT_FRAME_BYTES {
            bail!("Outbound frame size {} outside 1..={}", len, MAX_CLIENT_FRAME_BYTES);
        }
        Ok(frame)
    }
}

#[derive(Debug, Clone)]
pub enum InboundMessage {
    Welcome {
        v: i64,
        tier: String,
        enc: Encoding,
        you: i64,
        game_protocol: i64,
        maps: Vec<MapInfo>,
    },
    Error {
        msg: String,
    },
    Pong {
        ms: i64,
    },
    Rpc(RpcMessage),
    Raw {
        data: Vec<u8>,
        channel: u8,
        reliable: bool,
    },
    Unknown(String),
}

pub fn decode_text_frame(text: &str) -> Result<InboundMessage> {
    let val: Value = serde_json::from_str(text).context("Invalid JSON frame")?;
    let obj = val
        .as_object()
        .ok_or_else(|| anyhow!("Expected JSON object"))?;
    let t = obj
        .get("t")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("Missing string field 't'"))?;

    match t {
        "welcome" => {
            let v = json_as_i64(obj.get("v")).unwrap_or(1);
            let tier = obj
                .get("tier")
                .and_then(|x| x.as_str())
                .unwrap_or("full")
                .to_string();
            let enc = match obj.get("enc").and_then(|x| x.as_str()) {
                Some("bin") => Encoding::Bin,
                _ => Encoding::Json,
            };
            let you = json_as_i64(obj.get("you")).ok_or_else(|| anyhow!("Missing welcome.you"))?;
            let game_protocol = json_as_i64(obj.get("game_protocol")).unwrap_or(0);
            let mut maps = Vec::new();
            if let Some(arr) = obj.get("maps").and_then(|x| x.as_array()) {
                for m in arr {
                    if let (Some(id), Some(name)) = (
                        m.get("id").and_then(|x| x.as_str()),
                        m.get("name").and_then(|x| x.as_str()),
                    ) {
                        maps.push(MapInfo {
                            id: id.to_string(),
                            name: name.to_string(),
                        });
                    }
                }
            }
            Ok(InboundMessage::Welcome {
                v,
                tier,
                enc,
                you,
                game_protocol,
                maps,
            })
        }
        "error" => {
            let msg = obj
                .get("msg")
                .and_then(|x| x.as_str())
                .unwrap_or("Unknown server error")
                .to_string();
            Ok(InboundMessage::Error { msg })
        }
        "pong" => {
            let ms = json_as_i64(obj.get("ms")).unwrap_or(0);
            Ok(InboundMessage::Pong { ms })
        }
        "rpc" => {
            let node = obj
                .get("node")
                .and_then(|x| x.as_str())
                .ok_or_else(|| anyhow!("Missing rpc.node"))?
                .to_string();
            let method = obj
                .get("method")
                .and_then(|x| x.as_str())
                .ok_or_else(|| anyhow!("Missing rpc.method"))?
                .to_string();
            let channel = json_as_i64(obj.get("ch")).unwrap_or(0) as u8;
            let rel = obj.get("rel").and_then(|x| x.as_bool()).unwrap_or(true);
            let mode = if rel {
                TransferMode::Reliable
            } else {
                TransferMode::UnreliableOrdered
            };
            let mut args = Vec::new();
            if let Some(arr) = obj.get("args").and_then(|x| x.as_array()) {
                for a in arr {
                    args.push(Variant::from_json(a)?);
                }
            }
            Ok(InboundMessage::Rpc(RpcMessage {
                node,
                method,
                args,
                channel,
                mode,
            }))
        }
        "raw" => {
            let b64 = obj.get("data").and_then(|x| x.as_str()).unwrap_or("");
            let data = base64::engine::general_purpose::STANDARD
                .decode(b64)
                .unwrap_or_default();
            let channel = json_as_i64(obj.get("ch")).unwrap_or(0) as u8;
            let reliable = obj.get("rel").and_then(|x| x.as_bool()).unwrap_or(true);
            Ok(InboundMessage::Raw {
                data,
                channel,
                reliable,
            })
        }
        other => Ok(InboundMessage::Unknown(other.to_string())),
    }
}

pub fn decode_binary_frame(data: &[u8]) -> Result<InboundMessage> {
    if data.is_empty() {
        bail!("Empty binary frame");
    }
    match data[0] {
        BIN_TAG_RPC => Ok(InboundMessage::Rpc(RpcMessage::decode_bin(data)?)),
        BIN_TAG_RAW => {
            if data.len() < 3 {
                bail!("Truncated raw binary frame");
            }
            let mode = TransferMode::from_flags(data[1]);
            let channel = data[2];
            Ok(InboundMessage::Raw {
                data: data[3..].to_vec(),
                channel,
                reliable: mode.is_reliable(),
            })
        }
        tag => bail!("Unknown binary frame tag 0x{:02x}", tag),
    }
}

/// Frame a payload for Raw TCP (4-byte LE length prefix).
pub fn encode_tcp_frame(frame: &WireFrame) -> Vec<u8> {
    let payload: &[u8] = match frame {
        WireFrame::Text(s) => s.as_bytes(),
        WireFrame::Binary(b) => b.as_slice(),
    };
    let mut out = Vec::with_capacity(4 + payload.len());
    out.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    out.extend_from_slice(payload);
    out
}

/// Classify a raw TCP payload (first byte 0x00..=0x08 -> binary, else JSON text).
pub fn decode_tcp_payload(payload: &[u8]) -> Result<InboundMessage> {
    if payload.is_empty() {
        bail!("Empty TCP payload");
    }
    if payload[0] <= 0x08 {
        decode_binary_frame(payload)
    } else {
        let text = std::str::from_utf8(payload).context("Invalid UTF-8 in TCP JSON frame")?;
        decode_text_frame(text)
    }
}

fn json_as_i64(v: Option<&Value>) -> Option<i64> {
    let val = v?;
    val.as_i64().or_else(|| val.as_f64().map(|f| f as i64))
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
    fn tcp_framing_ping_example() {
        // spec-common.md §3.2 example
        let msg = OutboundMessage::Ping { ms: 7 };
        let frame = msg.encode(Encoding::Json).unwrap();
        let bytes = encode_tcp_frame(&frame);
        let expected = hex_to_bytes(
            "13 00 00 00 7b 22 74 22 3a 22 70 69 6e 67 22 2c 22 6d 73 22 3a 37 7d",
        );
        // serde_json key ordering may differ for object keys, so verify length + valid decode
        assert_eq!(bytes.len(), expected.len());
        assert_eq!(&bytes[0..4], &expected[0..4]);
        let parsed: Value = serde_json::from_slice(&bytes[4..]).unwrap();
        assert_eq!(parsed["t"], "ping");
        assert_eq!(parsed["ms"], 7);
    }

    #[test]
    fn binary_rpc_worked_examples_exact() {
        // Example 1: Net._hello('{"name":"3DS","color":1,"skin":0,"colors":[]}', 19)
        let rpc1 = RpcMessage::reliable(
            "Net",
            "_hello",
            vec![
                Variant::String(r#"{"name":"3DS","color":1,"skin":0,"colors":[]}"#.into()),
                Variant::Int(19),
            ],
        );
        let expected1 = hex_to_bytes(
            "03 02 00 03 00 4e 65 74 06 5f 68 65 6c 6c 6f 02
             04 00 00 00 2d 00 00 00 7b 22 6e 61 6d 65 22 3a
             22 33 44 53 22 2c 22 63 6f 6c 6f 72 22 3a 31 2c
             22 73 6b 69 6e 22 3a 30 2c 22 63 6f 6c 6f 72 73
             22 3a 5b 5d 7d 00 00 00 02 00 00 00 13 00 00 00",
        );
        let enc1 = rpc1.encode_bin().unwrap();
        assert_eq!(enc1, expected1);
        assert_eq!(RpcMessage::decode_bin(&enc1).unwrap(), rpc1);

        // Example 4: Main/Players/P_5._push_transform(Vector3(3, 0.2, 0), 1.5, -0.25, Vector3(0, 0, -5))
        let rpc4 = RpcMessage::unreliable_ordered(
            "Main/Players/P_5",
            "_push_transform",
            vec![
                Variant::Vector3(3.0, 0.2, 0.0),
                Variant::Float(1.5),
                Variant::Float(-0.25),
                Variant::Vector3(0.0, 0.0, -5.0),
            ],
        );
        let expected4 = hex_to_bytes(
            "03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
             73 2f 50 5f 35 0f 5f 70 75 73 68 5f 74 72 61 6e
             73 66 6f 72 6d 04 09 00 00 00 00 00 40 40 cd cc
             4c 3e 00 00 00 00 03 00 00 00 00 00 c0 3f 03 00
             00 00 00 00 80 be 09 00 00 00 00 00 00 00 00 00
             00 00 00 00 a0 c0",
        );
        let enc4 = rpc4.encode_bin().unwrap();
        assert_eq!(enc4, expected4);
        assert_eq!(RpcMessage::decode_bin(&enc4).unwrap(), rpc4);

        // Example 5: Main/Enemies._sync_enemies
        let expected5 = hex_to_bytes(
            "03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
             73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
             1e 00 00 00 01 00 00 00 01 00 00 00 24 00 00 00
             01 00 00 00 00 00 20 41 00 00 00 3f 00 00 80 c0
             20 00 00 00 01 00 00 00 00 00 c0 3f",
        );
        let dec5 = RpcMessage::decode_bin(&expected5).unwrap();
        assert_eq!(dec5.node, "Main/Enemies");
        assert_eq!(dec5.method, "_sync_enemies");
        assert_eq!(dec5.args[0], Variant::PackedInt32Array(vec![1]));
        assert_eq!(dec5.args[1], Variant::PackedVector3Array(vec![[10.0, 0.5, -4.0]]));
        assert_eq!(dec5.args[2], Variant::PackedFloat32Array(vec![1.5]));
        assert_eq!(dec5.encode_bin().unwrap(), expected5);

        // Example 7: WeatherManager._receive_phase(3, 1, 44.045620832318136)
        let expected7 = hex_to_bytes(
            "03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
             67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
             73 65 03 02 00 00 00 03 00 00 00 02 00 00 00 01
             00 00 00 03 00 01 00 4e 69 47 e7 d6 05 46 40",
        );
        let dec7 = RpcMessage::decode_bin(&expected7).unwrap();
        assert_eq!(dec7.args[0], Variant::Int(3));
        assert_eq!(dec7.args[1], Variant::Int(1));
        assert_eq!(dec7.args[2], Variant::Float(44.045620832318136));
        assert_eq!(dec7.encode_bin().unwrap(), expected7);

        // Example 8: GameManager/MutationRoll._sync_active([], []) with typed Array[String]
        let expected8 = hex_to_bytes(
            "03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
             2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0c 5f 73
             79 6e 63 5f 61 63 74 69 76 65 02 1c 00 01 00 04
             00 00 00 00 00 00 00 1c 00 01 00 04 00 00 00 00
             00 00 00",
        );
        let dec8 = RpcMessage::decode_bin(&expected8).unwrap();
        assert_eq!(dec8.node, "GameManager/MutationRoll");
        assert_eq!(dec8.method, "_sync_active");
        assert_eq!(dec8.args, vec![Variant::Array(vec![]), Variant::Array(vec![])]);
    }
}
