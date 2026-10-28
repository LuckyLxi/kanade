//! 极简 MQTT 5 客户端（WebSocket 承载），只实现 QQ 音乐 App 授权登录用到的部分：
//! CONNECT（含服务器重定向）/ SUBSCRIBE / 接收 PUBLISH（QoS 1 回 PUBACK）/ PINGREQ。

use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

const MAX_PACKET: usize = 256 * 1024;
const MAX_REDIRECTS: usize = 5;

pub struct Publish {
    pub topic: String,
    pub user_props: Vec<(String, String)>,
    pub payload: Vec<u8>,
}

impl Publish {
    pub fn user_prop(&self, key: &str) -> Option<&str> {
        self.user_props.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }
}

#[derive(Default)]
struct Props {
    user: Vec<(String, String)>,
    server_keep_alive: Option<u16>,
    server_reference: Option<String>,
}

pub struct MqttWs {
    ws: WebSocketStream<MaybeTlsStream<TcpStream>>,
    buf: Vec<u8>,
    /// 服务器要求的心跳间隔（秒），0 表示不需要。
    pub keep_alive: u16,
}

impl MqttWs {
    /// 连接 `wss://{host}{path}` 并完成 CONNECT；服务器用 0x9C/0x9D + Server Reference 重定向时跟随。
    pub async fn connect(
        host: &str,
        path: &str,
        client_id: &str,
        keep_alive: u16,
        auth_method: &str,
        user_props: &[(&str, &str)],
    ) -> Result<Self> {
        let mut path = path.to_string();
        for _ in 0..=MAX_REDIRECTS {
            let mut req = format!("wss://{host}{path}").into_client_request()?;
            let headers = req.headers_mut();
            headers.insert("Sec-WebSocket-Protocol", HeaderValue::from_static("mqtt"));
            headers.insert("Origin", HeaderValue::from_static("https://y.qq.com"));
            headers.insert("Referer", HeaderValue::from_static("https://y.qq.com/"));
            headers.insert("User-Agent", HeaderValue::from_static(super::client::UA));
            let (ws, _) = tokio_tungstenite::connect_async(req).await.context("MQTT websocket connect failed")?;
            let mut client = Self { ws, buf: Vec::new(), keep_alive };

            let mut body = enc_str("MQTT");
            body.push(5); // 协议版本
            body.push(0x02); // Clean Start
            body.extend(keep_alive.to_be_bytes());
            let mut props = vec![0x15];
            props.extend(enc_str(auth_method));
            props.extend(enc_user_props(user_props));
            body.extend(enc_props(&props));
            body.extend(enc_str(client_id));
            client.send(0x10, &body).await?;

            let (first, body) = client.next_packet().await?;
            if first >> 4 != 2 || body.len() < 2 {
                bail!("expected CONNACK, got packet type {}", first >> 4);
            }
            let reason = body[1];
            let props = if body.len() > 2 { parse_props(&body, &mut 2)? } else { Props::default() };
            match reason {
                0 => {
                    if let Some(ka) = props.server_keep_alive {
                        client.keep_alive = ka;
                    }
                    return Ok(client);
                }
                0x9C | 0x9D => {
                    let reference = props.server_reference.context("MQTT redirect without server reference")?;
                    // 路径最后一段若已是 host:port 则替换，否则追加
                    path = match path.trim_end_matches('/').rsplit_once('/') {
                        Some((parent, last)) if last.contains(':') => format!("{parent}/{reference}"),
                        _ => format!("{}/{reference}", path.trim_end_matches('/')),
                    };
                }
                code => bail!("MQTT CONNECT refused: 0x{code:02X}"),
            }
        }
        bail!("too many MQTT redirects")
    }

    pub async fn subscribe(&mut self, topic: &str, user_props: &[(&str, &str)]) -> Result<()> {
        let mut body = 1u16.to_be_bytes().to_vec();
        body.extend(enc_props(&enc_user_props(user_props)));
        body.extend(enc_str(topic));
        body.push(0); // QoS 0
        self.send(0x82, &body).await?;
        loop {
            let (first, body) = self.next_packet().await?;
            if first >> 4 != 9 {
                continue;
            }
            let mut pos = 2;
            parse_props(&body, &mut pos)?;
            match body.get(pos) {
                Some(code) if *code < 0x80 => return Ok(()),
                code => bail!("MQTT SUBSCRIBE refused: {code:?}"),
            }
        }
    }

    pub async fn ping(&mut self) -> Result<()> {
        self.send(0xC0, &[]).await
    }

    /// 等下一条 PUBLISH；其它报文（PINGRESP 等）跳过，DISCONNECT 视为错误。
    pub async fn next_publish(&mut self) -> Result<Publish> {
        loop {
            let (first, body) = self.next_packet().await?;
            match first >> 4 {
                3 => {
                    let qos = (first >> 1) & 0x03;
                    let mut pos = 0;
                    let topic = read_str(&body, &mut pos)?;
                    if qos > 0 {
                        let id = body.get(pos..pos + 2).context("truncated PUBLISH")?.to_vec();
                        pos += 2;
                        if qos == 1 {
                            self.send(0x40, &id).await?;
                        }
                    }
                    let props = parse_props(&body, &mut pos)?;
                    return Ok(Publish { topic, user_props: props.user, payload: body[pos..].to_vec() });
                }
                14 => bail!("MQTT server disconnected"),
                _ => {}
            }
        }
    }

    async fn send(&mut self, first: u8, body: &[u8]) -> Result<()> {
        let mut packet = vec![first];
        packet.extend(enc_varint(body.len()));
        packet.extend(body);
        self.ws.send(Message::Binary(packet)).await?;
        Ok(())
    }

    /// 一个 WebSocket 帧里可能有半个或多个 MQTT 报文，攒够一个完整报文再返回。
    async fn next_packet(&mut self) -> Result<(u8, Vec<u8>)> {
        loop {
            if let Some((header_len, body_len)) = packet_len(&self.buf)? {
                if self.buf.len() >= header_len + body_len {
                    let first = self.buf[0];
                    let body = self.buf[header_len..header_len + body_len].to_vec();
                    self.buf.drain(..header_len + body_len);
                    return Ok((first, body));
                }
            }
            match self.ws.next().await.context("MQTT websocket closed")?? {
                Message::Binary(data) => self.buf.extend(data),
                Message::Close(_) => bail!("MQTT websocket closed"),
                _ => {}
            }
        }
    }
}

/// 返回（固定报头长度，剩余长度）；数据还不够解析报头时返回 None。
fn packet_len(buf: &[u8]) -> Result<Option<(usize, usize)>> {
    let mut len = 0usize;
    for i in 0..4 {
        let Some(byte) = buf.get(1 + i) else { return Ok(None) };
        len |= ((byte & 0x7F) as usize) << (7 * i);
        if byte & 0x80 == 0 {
            if len > MAX_PACKET {
                bail!("MQTT packet too large");
            }
            return Ok(Some((2 + i, len)));
        }
    }
    bail!("malformed MQTT remaining length")
}

fn enc_varint(mut n: usize) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let mut byte = (n % 128) as u8;
        n /= 128;
        if n > 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if n == 0 {
            return out;
        }
    }
}

fn enc_str(s: &str) -> Vec<u8> {
    let mut out = (s.len() as u16).to_be_bytes().to_vec();
    out.extend(s.as_bytes());
    out
}

fn enc_user_props(pairs: &[(&str, &str)]) -> Vec<u8> {
    let mut out = Vec::new();
    for (k, v) in pairs {
        out.push(0x26);
        out.extend(enc_str(k));
        out.extend(enc_str(v));
    }
    out
}

fn enc_props(props: &[u8]) -> Vec<u8> {
    let mut out = enc_varint(props.len());
    out.extend(props);
    out
}

fn read_varint(data: &[u8], pos: &mut usize) -> Result<usize> {
    let mut value = 0usize;
    for i in 0..4 {
        let byte = *data.get(*pos).context("truncated varint")?;
        *pos += 1;
        value |= ((byte & 0x7F) as usize) << (7 * i);
        if byte & 0x80 == 0 {
            return Ok(value);
        }
    }
    bail!("malformed varint")
}

fn read_bytes<'a>(data: &'a [u8], pos: &mut usize) -> Result<&'a [u8]> {
    let len = u16::from_be_bytes(data.get(*pos..*pos + 2).context("truncated length")?.try_into()?) as usize;
    let bytes = data.get(*pos + 2..*pos + 2 + len).context("truncated data")?;
    *pos += 2 + len;
    Ok(bytes)
}

fn read_str(data: &[u8], pos: &mut usize) -> Result<String> {
    Ok(String::from_utf8_lossy(read_bytes(data, pos)?).into_owned())
}

fn parse_props(data: &[u8], pos: &mut usize) -> Result<Props> {
    let len = read_varint(data, pos)?;
    let end = *pos + len;
    if end > data.len() {
        bail!("truncated MQTT properties");
    }
    let mut props = Props::default();
    while *pos < end {
        let id = data[*pos];
        *pos += 1;
        match id {
            0x01 | 0x17 | 0x19 | 0x24 | 0x25 | 0x28 | 0x29 | 0x2A => *pos += 1,
            0x13 => {
                props.server_keep_alive = Some(u16::from_be_bytes(data.get(*pos..*pos + 2).context("truncated")?.try_into()?));
                *pos += 2;
            }
            0x21..=0x23 => *pos += 2,
            0x02 | 0x11 | 0x18 | 0x27 => *pos += 4,
            0x0B => {
                read_varint(data, pos)?;
            }
            0x1C => props.server_reference = Some(read_str(data, pos)?),
            0x03 | 0x08 | 0x12 | 0x15 | 0x1A | 0x1F | 0x09 | 0x16 => {
                read_bytes(data, pos)?;
            }
            0x26 => {
                let k = read_str(data, pos)?;
                let v = read_str(data, pos)?;
                props.user.push((k, v));
            }
            other => bail!("unknown MQTT property 0x{other:02X}"),
        }
    }
    *pos = end;
    Ok(props)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn varint_round_trip() {
        for n in [0, 127, 128, 16_383, 16_384, 200_000] {
            let enc = enc_varint(n);
            assert_eq!(read_varint(&enc, &mut 0).unwrap(), n);
        }
    }

    #[test]
    fn parses_connack_props_and_partial_packets() {
        // CONNACK：flags 0、reason 0、属性 = Server Keep Alive 30 + user property (server, x)
        let mut props = vec![0x13, 0, 30];
        props.extend(enc_user_props(&[("server", "x")]));
        let mut body = vec![0, 0];
        body.extend(enc_props(&props));
        let mut packet = vec![0x20];
        packet.extend(enc_varint(body.len()));
        packet.extend(&body);

        assert_eq!(packet_len(&packet[..1]).unwrap(), None);
        assert_eq!(packet_len(&packet).unwrap(), Some((2, body.len())));
        let parsed = parse_props(&body, &mut 2).unwrap();
        assert_eq!(parsed.server_keep_alive, Some(30));
        assert_eq!(parsed.user, vec![("server".to_string(), "x".to_string())]);
    }
}
