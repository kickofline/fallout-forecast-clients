#![allow(dead_code)]

use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;

use super::frame::{
    decode_binary_frame, decode_tcp_payload, decode_text_frame, encode_tcp_frame, Encoding,
    InboundMessage, OutboundMessage, WireFrame, MAX_SERVER_FRAME_BYTES,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportEndpoint {
    WebSocket(String),
    Tcp(String),
}

impl TransportEndpoint {
    pub fn display(&self) -> String {
        match self {
            TransportEndpoint::WebSocket(u) => u.clone(),
            TransportEndpoint::Tcp(addr) => format!("tcp://{}", addr),
        }
    }
}

#[derive(Debug)]
pub enum NetEvent {
    Connected,
    Message(InboundMessage),
    Disconnected(String),
}

pub struct NetClientHandle {
    tx: mpsc::UnboundedSender<OutboundMessage>,
    rx: mpsc::UnboundedReceiver<NetEvent>,
    pub enc: Encoding,
}

impl NetClientHandle {
    pub fn send(&self, msg: OutboundMessage) -> Result<()> {
        self.tx
            .send(msg)
            .map_err(|_| anyhow::anyhow!("Network send channel closed"))
    }

    pub fn try_recv(&mut self) -> Option<NetEvent> {
        self.rx.try_recv().ok()
    }

    pub async fn recv(&mut self) -> Option<NetEvent> {
        self.rx.recv().await
    }
}

pub fn spawn_connection(endpoint: TransportEndpoint, enc: Encoding) -> NetClientHandle {
    let (tx_out, rx_out) = mpsc::unbounded_channel::<OutboundMessage>();
    let (tx_in, rx_in) = mpsc::unbounded_channel::<NetEvent>();

    tokio::spawn(async move {
        let res = match endpoint {
            TransportEndpoint::WebSocket(url) => run_ws(url, enc, rx_out, tx_in.clone()).await,
            TransportEndpoint::Tcp(addr) => run_tcp(addr, enc, rx_out, tx_in.clone()).await,
        };
        let reason = match res {
            Ok(msg) => msg,
            Err(e) => format!("{:#}", e),
        };
        let _ = tx_in.send(NetEvent::Disconnected(reason));
    });

    NetClientHandle {
        tx: tx_out,
        rx: rx_in,
        enc,
    }
}

async fn run_ws(
    url: String,
    enc: Encoding,
    mut rx_out: mpsc::UnboundedReceiver<OutboundMessage>,
    tx_in: mpsc::UnboundedSender<NetEvent>,
) -> Result<String> {
    let (ws_stream, _resp) = tokio_tungstenite::connect_async(&url)
        .await
        .with_context(|| format!("WebSocket connect to {}", url))?;
    let _ = tx_in.send(NetEvent::Connected);

    let (mut sink, mut stream) = ws_stream.split();

    loop {
        tokio::select! {
            maybe_out = rx_out.recv() => {
                match maybe_out {
                    Some(msg) => {
                        let is_leave = matches!(msg, OutboundMessage::Leave);
                        let wire = msg.encode(enc)?;
                        let ws_msg = match wire {
                            WireFrame::Text(s) => Message::Text(s.into()),
                            WireFrame::Binary(b) => Message::Binary(b.into()),
                        };
                        sink.send(ws_msg).await.context("WebSocket send failed")?;
                        if is_leave {
                            let _ = sink.close().await;
                            return Ok("Left session".to_string());
                        }
                    }
                    None => {
                        let _ = sink.close().await;
                        return Ok("Client closed connection".to_string());
                    }
                }
            }
            maybe_in = stream.next() => {
                match maybe_in {
                    Some(Ok(Message::Text(text))) => {
                        match decode_text_frame(text.as_str()) {
                            Ok(m) => {
                                if tx_in.send(NetEvent::Message(m)).is_err() {
                                    return Ok("Receiver dropped".to_string());
                                }
                            }
                            Err(e) => {
                                let _ = tx_in.send(NetEvent::Message(InboundMessage::Error {
                                    msg: format!("Local decode error: {}", e),
                                }));
                            }
                        }
                    }
                    Some(Ok(Message::Binary(bin))) => {
                        match decode_binary_frame(&bin) {
                            Ok(m) => {
                                if tx_in.send(NetEvent::Message(m)).is_err() {
                                    return Ok("Receiver dropped".to_string());
                                }
                            }
                            Err(e) => {
                                let _ = tx_in.send(NetEvent::Message(InboundMessage::Error {
                                    msg: format!("Local binary decode error: {}", e),
                                }));
                            }
                        }
                    }
                    Some(Ok(Message::Ping(payload))) => {
                        let _ = sink.send(Message::Pong(payload)).await;
                    }
                    Some(Ok(Message::Pong(_))) => {}
                    Some(Ok(Message::Close(frame))) => {
                        let reason = frame
                            .map(|f| f.reason.to_string())
                            .filter(|s| !s.is_empty())
                            .unwrap_or_else(|| "Server closed connection".to_string());
                        return Ok(reason);
                    }
                    Some(Ok(Message::Frame(_))) => {}
                    Some(Err(e)) => {
                        return Err(e).context("WebSocket stream error");
                    }
                    None => {
                        return Ok("Connection closed by server".to_string());
                    }
                }
            }
        }
    }
}

async fn run_tcp(
    addr: String,
    enc: Encoding,
    mut rx_out: mpsc::UnboundedReceiver<OutboundMessage>,
    tx_in: mpsc::UnboundedSender<NetEvent>,
) -> Result<String> {
    let stream = TcpStream::connect(&addr)
        .await
        .with_context(|| format!("TCP connect to {}", addr))?;
    let _ = stream.set_nodelay(true);
    let _ = tx_in.send(NetEvent::Connected);

    let (mut reader, mut writer) = stream.into_split();

    let tx_in_reader = tx_in.clone();
    let read_task = tokio::spawn(async move {
        let mut len_buf = [0u8; 4];
        loop {
            match reader.read_exact(&mut len_buf).await {
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    return Ok::<String, anyhow::Error>("Connection closed by server".to_string());
                }
                Err(e) => return Err(e).context("TCP read length failed"),
            }
            let len = u32::from_le_bytes(len_buf) as usize;
            if len == 0 || len > MAX_SERVER_FRAME_BYTES {
                bail!("Invalid TCP frame length {}", len);
            }
            let mut payload = vec![0u8; len];
            reader
                .read_exact(&mut payload)
                .await
                .context("TCP read payload failed")?;
            match decode_tcp_payload(&payload) {
                Ok(m) => {
                    if tx_in_reader.send(NetEvent::Message(m)).is_err() {
                        return Ok("Receiver dropped".to_string());
                    }
                }
                Err(e) => {
                    let _ = tx_in_reader.send(NetEvent::Message(InboundMessage::Error {
                        msg: format!("Local TCP decode error: {}", e),
                    }));
                }
            }
        }
    });

    let write_task = tokio::spawn(async move {
        while let Some(msg) = rx_out.recv().await {
            let is_leave = matches!(msg, OutboundMessage::Leave);
            let wire = msg.encode(enc)?;
            let bytes = encode_tcp_frame(&wire);
            writer.write_all(&bytes).await.context("TCP write failed")?;
            writer.flush().await.context("TCP flush failed")?;
            if is_leave {
                let _ = writer.shutdown().await;
                return Ok::<String, anyhow::Error>("Left session".to_string());
            }
        }
        let _ = writer.shutdown().await;
        Ok("Client closed connection".to_string())
    });

    tokio::select! {
        r = read_task => {
            r.context("TCP reader join error")?
        }
        w = write_task => {
            w.context("TCP writer join error")?
        }
    }
}
