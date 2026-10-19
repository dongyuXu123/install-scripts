#!/usr/bin/env python3
"""本地 TLS 代理：把 files.pythonhosted.org/pypi.org 的请求转给清华 PyPI 镜像。

- 对 MITM 域名：终结客户端 TLS（自签证书），以真实 SNI+Host 连接清华源，
  逐请求改写 Host 并强制 Connection: close（简化 h1 状态机）。
- 其它域名：CONNECT 盲转发。
用法: python3 mitm-proxy.py [端口，默认 8932]
"""
import asyncio
import ssl
import sys
from pathlib import Path

LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8932
UPSTREAM_HOST = "pypi.tuna.tsinghua.edu.cn"
UPSTREAM_IP = "101.6.15.130"
MITM_HOSTS = {"files.pythonhosted.org", "pypi.org"}
CERT_FILE = str(Path(__file__).with_name("mitm-leaf.pem"))
KEY_FILE = str(Path(__file__).with_name("mitm-leaf-key.pem"))

_server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
_server_ctx.load_cert_chain(CERT_FILE, KEY_FILE)
_server_ctx.set_alpn_protocols(["http/1.1"])

_client_ctx = ssl.create_default_context()


async def pump(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while chunk := await reader.read(262144):
            writer.write(chunk)
            await writer.drain()
    except (ConnectionError, ssl.SSLError, TimeoutError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def mitm_stream(c_reader: asyncio.StreamReader, c_writer: asyncio.StreamWriter) -> None:
    """终结 TLS 后的明文 h1 流：逐请求改写 Host 转发，响应按连接关闭截断。"""
    try:
        u_reader, u_writer = await asyncio.open_connection(
            UPSTREAM_IP, 443, ssl=_client_ctx, server_hostname=UPSTREAM_HOST
        )
    except Exception as exc:
        print(f"upstream connect failed: {exc!r}", flush=True)
        return
    _ssl = u_writer.get_extra_info("ssl_object")
    print(f"UPSTREAM tls={_ssl.version()} alpn={_ssl.selected_alpn_protocol()} peer={u_writer.get_extra_info('peername')}", flush=True)
    await asyncio.sleep(0.05)
    try:
        head = await c_reader.readuntil(b"\r\n\r\n")
        lines = head.split(b"\r\n")
        print(f"REQ {head.decode(errors='replace')!r}", flush=True)
        out = []
        for line in lines:
            low = line.lower()
            if low.startswith(b"host:"):
                out.append(b"Host: " + UPSTREAM_HOST.encode())
            elif low.startswith(b"connection:") or low.startswith(b"proxy-"):
                continue
            else:
                out.append(line)
        while out and out[-1] == b"":
            out.pop()
        out.append(b"Connection: close")
        out.append(b"")
        out.append(b"")
        req = b"\r\n".join(out)
        print(f"OUT {req.decode(errors='replace')!r}", flush=True)
        u_writer.write(req)
        await u_writer.drain()
        await asyncio.sleep(0.2)
        peek = await asyncio.wait_for(u_reader.read(64), 8)
        print(f"PEEK {peek[:48]!r} eof={u_reader.at_eof()}", flush=True)
        status_line = peek + await u_reader.readuntil(b"\r\n\r\n")
        print(f"RSP {status_line.split(bytes((13, 10)))[0].decode(errors='replace')}", flush=True)
        c_writer.write(status_line)
        await c_writer.drain()
        await pump(u_reader, c_writer)  # 响应直至上游关闭
    except (asyncio.IncompleteReadError, ConnectionError, ssl.SSLError) as exc:
        print(f"MITM-ERR {exc!r}", flush=True)
    finally:
        for w in (u_writer, c_writer):
            try:
                w.close()
            except Exception:
                pass


async def handle(client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter) -> None:
    try:
        line = await client_reader.readuntil(b"\r\n\r\n")
        method, target = line.split(b"\r\n")[0].split(b" ")[0:2]
        if method != b"CONNECT":
            return
        host = target.rsplit(b":", 1)[0].decode()
        client_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        await client_writer.drain()
        if host in MITM_HOSTS:
            await client_writer.start_tls(_server_ctx)
            await mitm_stream(client_reader, client_writer)
        else:
            remote_reader, remote_writer = await asyncio.open_connection(host, 443)
            t1 = asyncio.create_task(pump(client_reader, remote_writer))
            await pump(remote_reader, client_writer)
            t1.cancel()
    except Exception:
        pass
    finally:
        try:
            client_writer.close()
        except Exception:
            pass


async def main() -> None:
    server = await asyncio.start_server(handle, "127.0.0.1", LISTEN_PORT)
    print(f"MITM proxy on 127.0.0.1:{LISTEN_PORT}, upstream {UPSTREAM_HOST}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
