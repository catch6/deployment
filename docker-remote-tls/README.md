# Docker 远程安全访问

使用方法

- IP: 服务端公网 IP
- PASSWD: 证书密码
- DIR: 证书生成目录
- PERIOD: 证书有效期, 单位: 天

```shell
curl -sSL https://ghproxy.com/https://raw.githubusercontent.com/catch6/deployment/main/docker-remote-tls/main.sh | bash -s <IP> <PASSWD> [DIR] [PERIOD]
```
