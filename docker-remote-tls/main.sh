#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE="\033[0;35m"
CYAN='\033[0;36m'
PLAIN='\033[0m'

read -p "请输入服务器IP(默认自动检测): " IP
IP=${IP:-$(curl -s https://api4.ipify.org)}
echo -e "${BLUE}IP: ${IP}${PLAIN}"

read -p "请输入证书私钥密码(默认随机12位密码): " PASSWD
PASSWD=${PASSWD:-$(LC_CTYPE=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)}
echo -e "${BLUE}证书私钥密码: ${PASSWD}${PLAIN}"

read -p "请输入证书保存目录(默认/data/base/docker): " DIR
DIR=${DIR:-"/data/base/docker"}
echo -e "${BLUE}证书保存目录: ${DIR}${PLAIN}"

read -p "请输入证书有效天数(默认36500): " PERIOD
PERIOD=${PERIOD:-36500}
echo -e "${BLUE}证书有效天数: ${PERIOD}${PLAIN}"

mkdir -p ${DIR}/client
cd ${DIR}/client

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

cp ca.pem ../ca.pem
mv ca-key.pem ../ca-key.pem
mv server-cert.pem ../cert.pem
mv server-key.pem ../key.pem

mkdir -p /etc/systemd/system/docker.service.d
cat >/etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H tcp://${IP}:2376 --tls --tlsverify --tlscacert=${DIR}/ca.pem --tlscert=${DIR}/cert.pem --tlskey=${DIR}/key.pem --containerd=/run/containerd/containerd.sock
EOF

systemctl daemon-reload
systemctl restart docker

mv client-cert.pem cert.pem
mv client-key.pem key.pem
tar -zcvf ../client.tar.gz ca.pem cert.pem key.pem

cd ${DIR}
mv client client
tar -zcvf client.tar.gz ca.pem client/cert.pem client/key.pem

echo -e "${GREEN}客户端证书生成成功, 路径: ${DIR}/client.tar.gz${PLAIN}"
echo -e "${GREEN}可使用 sz client.tar.gz 下载到本地进行 Docker 远程安全连接${PLAIN}"
