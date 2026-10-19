# hermes-install

Hermes Agent（Nous Research）安装/更新时的本地 PyPI 加速代理。2026-10-18 随
Hermes Agent v0.22.2 一起在本机（Ubuntu 26.04）部署并验证可用。

## 背景

- Hermes Agent 用 `uv sync --frozen` 安装依赖，下载地址被 lockfile 钉死为
  `pypi.org` / `files.pythonhosted.org` 官方域名，`UV_INDEX_URL` 等变量无法重定向
- 国内网络对 Fastly（PyPI 官方 CDN）限速严重（实测 5–140 KB/s，四个 anycast 边缘全一样）
- 清华 tuna 镜像在**完全相同的路径**上提供字节级一致的文件，但客户端连不上
  镜像域名（URL 里的域名改不了）
- 解决办法：本地起一个代理，把这两个域名的 TLS 流量"接过来"，改写 Host 后
  转发给 tuna —— 客户端以为自己在连官方源，实际走镜像

## 组成

| 文件 | 说明 |
|---|---|
| `mitm-proxy.py` | 代理本体，监听 `127.0.0.1:8932`。对 MITM 域名终结 TLS 后改写 Host 转发给 tuna（强制 `Connection: close`）；其它域名 CONNECT 盲转发，不做任何处理 |
| `hermes-pypi-proxy.service` | systemd 用户级单元，开机自启、崩溃 3 秒后自动重启 |

证书（CA + 叶子证书/私钥）**不入库**——私钥传公开仓库等于把中间人能力送人。
新机器按下面两条命令重新生成即可。

## 部署步骤（新机器）

```bash
# 1. 放置脚本
mkdir -p ~/hermes-install && cd ~/hermes-install
#    把 mitm-proxy.py 放到这里

# 2. 生成证书（CA 有效期 10 年；叶子 SAN 覆盖两个 PyPI 域名）
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout mitm-ca-key.pem -out mitm-ca.pem \
  -days 3650 -subj "/CN=Hermes Local Proxy CA"
openssl req -newkey rsa:2048 -nodes \
  -keyout mitm-leaf-key.pem -out mitm-leaf.csr \
  -subj "/CN=files.pythonhosted.org"
printf 'subjectAltName=DNS:files.pythonhosted.org,DNS:pypi.org,DNS:localhost\n' > mitm-leaf.ext
openssl x509 -req -in mitm-leaf.csr \
  -CA mitm-ca.pem -CAkey mitm-ca-key.pem -CAcreateserial \
  -out mitm-leaf.pem -days 3650 -extfile mitm-leaf.ext
rm -f mitm-leaf.csr mitm-leaf.ext
# mitm-ca-key.pem 生成叶子后即可删除（本机就是这么做的，只留 CA 证书）

# 3. 安装 systemd 用户单元（注意：ExecStart 里是绝对路径，用户名不同要改）
mkdir -p ~/.config/systemd/user
cp hermes-pypi-proxy.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now hermes-pypi-proxy
```

## 客户端接入

Hermes 的环境变量集中在 `~/.hermes/.env`，hermes / uv / pm 启动时自动读取：

```ini
SSL_CERT_FILE=/home/<你>/hermes-install/mitm-ca.pem
HTTPS_PROXY=http://127.0.0.1:8932
NO_PROXY=127.0.0.1,localhost
```

配好后 `hermes update`、`hermes pm install` 无需任何额外操作。

## 验证与排查

```bash
systemctl --user status hermes-pypi-proxy      # 服务状态
journalctl --user -u hermes-pypi-proxy -f      # 实时日志（REQ/OUT/RSP 行可看每个请求）
```

## 备注

- tuna 拒绝伪造 SNI/Host，改 hosts 文件的方案走不通，所以才用代理
- 本代理只加速 PyPI 两个域名，其它流量原样盲转发，不影响正常上网
