#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE="\033[0;35m"
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 服务器 IP, 如 192.168.0.1
IP=$1
# RSA 私钥密码, 如 123456
PASSWD=$2
# 证书保存目录, 默认 /data/base/docker
DIR=${3:-"/data/base/docker"}
# 证书有效期天数，默认 36500，代表 100 年
PERIOD=${4:-36500}

mkdir -p $DIR/temp
cd $DIR/temp

# 为 CA 创建私钥
openssl genrsa -aes256 -passout pass:"${PASSWD}" -out ca-key.pem 4096
# 用 CA 私钥生成公钥
openssl req -new -x509 -days ${PERIOD} -key ca-key.pem -passin pass:"${PASSWD}" -sha256 -out ca.pem -subj "/C=CN/ST=./L=./O=./CN=${IP}"

# 为服务端创建私钥
openssl genrsa -out server-key.pem 4096
# 创建证书签名请求并发送到 CA
openssl req -subj "/CN=${IP}" -sha256 -new -key server-key.pem -out server.csr
# 指定可以远程连接 Docker 的 ip
echo "subjectAltName = IP:${IP},IP:0.0.0.0" >extfile.cnf
# 将 Docker 守护程序密钥的扩展使用属性设置为仅用于服务器身份验证
echo "extendedKeyUsage = serverAuth" >>extfile.cnf
# 生成服务端签名证书
openssl x509 -req -days ${PERIOD} -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem -passin "pass:${PASSWD}" -CAcreateserial -out server-cert.pem -extfile extfile.cnf
# 清除临时文件
rm -f server.csr extfile.cnf

# 为客户端创建私钥
openssl genrsa -out client-key.pem 4096
# 创建客户端签名请求证书
openssl req -subj '/CN=client' -new -key client-key.pem -out client.csr
# 将证书设置为客户端认证可用
echo "extendedKeyUsage = clientAuth" >extfile.cnf
# 生成证书文件
openssl x509 -req -days ${PERIOD} -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem -passin "pass:${PASSWD}" -CAcreateserial -out client-cert.pem -extfile extfile.cnf
# 清除临时文件
rm -f client.csr extfile.cnf

chmod 400 ca-key.pem server-key.pem client-key.pem

chmod 444 ca.pem server-cert.pem client-cert.pem

mv ca.pem $DIR/ca.pem
mv server-cert.pem $DIR/cert.pem
mv server-key.pem $DIR/key.pem
mv client-cert.pem $DIR/temp/cert.pem
mv client-key.pem $DIR/temp/key.pem

cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://${IP}:2376 --tls --tlsverify --tlscacert=/data/base/docker/cert/ca.pem --tlscert=/data/base/docker/cert.pem --tlskey=/data/base/docker/key.pem  --containerd=/run/containerd/containerd.sock
EOF

systemctl daemon-reload
systemctl restart docker

tar -zcvf $DIR/client.tar.gz $DIR/ca.pem $DIR/temp/cert.pem $DIR/temp/key.pem

echo -e "${GREEN}客户端证书生成成功, 路径: ${DIR}/client.tar.gz${PLAIN}"
