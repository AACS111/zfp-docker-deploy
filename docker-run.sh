#!/bin/bash

# 如果命令以非零状态退出，则立即退出脚本。
set -e
# 在替换时，将未设置的变量视为错误。
set -u
# 管道命令的返回值将是最后一个以非零状态退出的命令的退出状态，
# 或者如果所有命令都成功退出则返回零。
set -o pipefail

# ========== Docker 安装配置 ==========

# 1. 更新软件包索引并安装必要的依赖
echo "--> 正在更新软件包索引并安装必要的依赖..."
sudo dnf makecache
sudo dnf install -y dnf-utils openssl # 确保 openssl 已安装

# 2. 卸载旧版本的 Docker（如果存在）
echo "--> 正在尝试移除可能存在的旧 Docker 软件包..."
sudo dnf remove -y docker \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-engine \
                  docker-ce \
                  docker-ce-cli \
                  containerd.io \
                  runc || true

# 3. 设置 Docker 软件仓库
echo "--> 正在添加官方 Docker 软件仓库..."
sudo yum config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo sed -i 's/download.docker.com/mirrors.aliyun.com\/docker-ce/g' /etc/yum.repos.d/docker-ce.repo || echo "Sed command skipped or failed, continuing..."

# 4. 安装 Docker 引擎
echo "--> 正在安装 Docker 引擎..."
sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 5. 确保 Docker 服务启动并设置开机自启（稍后会重启）
echo "--> 正在启动并设置开机自启 Docker 服务 (初始启动)..."
sudo systemctl start docker
sudo systemctl enable docker
sudo systemctl status docker --no-pager

# 6. 确保 /home/docker 和数据目录存在
DOCKER_DATA="/home/docker/docker-data"

echo "--> 确保 Docker 数据目录 '$DOCKER_DATA' 存在..."
sudo mkdir -p $DOCKER_DATA

# ========== 询问用户是否启用 TLS ==========
ENABLE_TLS=""
while [[ "$ENABLE_TLS" != "yes" && "$ENABLE_TLS" != "no" ]]; do
    read -p "是否启用 TLS 以允许安全的远程 Docker 连接? (yes/no): " user_input
    ENABLE_TLS=$(echo "$user_input" | tr '[:upper:]' '[:lower:]') # 转为小写
    if [[ "$ENABLE_TLS" != "yes" && "$ENABLE_TLS" != "no" && "$ENABLE_TLS" != "y" && "$ENABLE_TLS" != "n" ]]; then
        echo "无效输入，请输入 'yes' 或 'no'."
        ENABLE_TLS="" # 重置以便循环继续
    elif [[ "$ENABLE_TLS" == "y" ]]; then
         ENABLE_TLS="yes"
    elif [[ "$ENABLE_TLS" == "n" ]]; then
         ENABLE_TLS="no"
    fi
done

# ========== 根据用户选择执行操作 ==========
if [[ "$ENABLE_TLS" == "yes" ]]; then
    # --- 执行 TLS 证书生成 ---
    echo "===== 用户选择启用 TLS，开始生成 Docker TLS 证书 ====="

    # --- TLS 相关配置信息 ---
    SERVER_IP="10.211.55.6"   # ！！！ 重要: 使用Docker客户端连接到服务器的实际IP地址
    PASSWORD="123456"        # ！！！ 重要: 请修改为强密码  ！!
    COUNTRY="CN"
    STATE="xx省"
    CITY="xx市"
    ORGANIZATION="xxxx有限公司"
    ORGANIZATIONAL_UNIT="Dev"
    EMAIL="123456@qq.com"
    CERT_DIR="/home/docker/tls" # 定义证书存放目录
    # --- 配置结束 ---
    echo "--> 确保 '/home/docker/tls' 目录存在..."
    sudo mkdir -p $CERT_DIR

    echo "--> 切换到证书目录: $CERT_DIR"
    cd "$CERT_DIR"

    echo "--> 生成 CA 私钥 (ca-key.pem)..."
    openssl genrsa -aes256 -passout pass:$PASSWORD -out ca-key.pem 4096

    echo "--> 生成 CA 证书 (ca.pem)..."
    openssl req -new -x509 -passin "pass:$PASSWORD" -days 3650 -key ca-key.pem -sha256 -out ca.pem \
      -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=$SERVER_IP/emailAddress=$EMAIL"

    echo "--> 生成服务器私钥 (server-key.pem)..."
    openssl genrsa -out server-key.pem 4096

    echo "--> 生成服务器证书签名请求 (server.csr)..."
    openssl req -subj "/CN=$SERVER_IP" -new -key server-key.pem -out server.csr

    echo "--> 使用 CA 签发服务器证书 (server-cert.pem)..."
    echo "subjectAltName = IP:$SERVER_IP" > server-ext.cnf
    openssl x509 -req -days 3650 -in server.csr -CA ca.pem -CAkey ca-key.pem \
      -passin "pass:$PASSWORD" -CAcreateserial -out server-cert.pem -extfile server-ext.cnf

    echo "--> 生成客户端私钥 (key.pem)..."
    openssl genrsa -out key.pem 4096

    echo "--> 生成客户端证书签名请求 (client.csr)..."
    openssl req -subj '/CN=client' -new -key key.pem -out client.csr

    echo "--> 创建客户端证书扩展文件 (extfile.cnf)..."
    echo "extendedKeyUsage=clientAuth" > extfile.cnf

    echo "--> 使用 CA 签发客户端证书 (cert.pem)..."
    openssl x509 -req -days 3650 -in client.csr -CA ca.pem -CAkey ca-key.pem \
      -passin "pass:$PASSWORD" -CAcreateserial -out cert.pem -extfile extfile.cnf

    echo "--> 调整证书和密钥文件权限..."
    # 使用 sudo 确保权限设置成功，即使脚本以非 root 用户执行（但需要 sudo 权限）
    sudo chmod 0774 ca-key.pem key.pem server-key.pem
    sudo chmod 0774 ca.pem server-cert.pem cert.pem

    echo "--> 清理临时文件..."
    rm -f client.csr server.csr server-ext.cnf extfile.cnf ca.srl

    echo "===== TLS 证书生成完成 ====="


else

    # --- 用户选择不启用 TLS ---
    echo "===== 用户选择不启用 TLS ====="
    echo "--> 仅配置镜像加速和数据目录..."

fi

    # --- 配置 daemon.json  ---
    echo "--> 正在写入 '/etc/docker/daemon.json' 配置文件..."
    sudo bash -c 'cat <<EOF > /etc/docker/daemon.json
{
  "registry-mirrors": ["https://zhengfp.cn"],
  "data-root": "$DOCKER_DATA"
}

EOF'


# ========== 应用配置并完成后续步骤 ==========
echo "--> '/etc/docker/daemon.json' 配置写入完成。内容如下:"
sudo cat /etc/docker/daemon.json

# 7. 重启 Docker 服务以应用配置
echo "--> 正在重启 Docker 服务以应用 daemon.json 配置..."
sudo systemctl restart docker

# 8. 验证 Docker 服务状态
echo "--> 正在检查 Docker 服务状态，确认配置已生效..."
sudo systemctl status docker --no-pager

# 9. 将当前用户添加到 docker 组（可选）
echo "--> 正在将当前用户 ($USER) 添加到 'docker' 用户组..."
sudo usermod -aG docker $USER
echo "# 重要提示：                                                         #"
echo "# 用户组更改需要 退出登录 并 重新登录 才能生效。                    #"
echo "# 或者，运行 'newgrp docker' 启动具有新组成员身份的新 Shell。         #"


# 10. 最终验证说明 (根据 TLS 选择显示不同信息)
echo "===== Docker 安装和配置脚本执行完毕 ====="
echo "镜像加速器: https://zhengfp.cn"
echo "数据目录: $DOCKER_DATA"

if [[ "$ENABLE_TLS" == "yes" ]]; then
    echo "######################################################################"
    echo "                                                          "
    echo "# 重要提示：需要到/usr/lib/systemd/system/docker.service目录去配置Docker 的TLS用于远程服务器连接,执行下面命令"
    echo "# >>> 打开docker.service文件                                   "
    echo "   vim /usr/lib/systemd/system/docker.service             "
    echo ""
    echo "# >>> 将下面内容加入到 [Service] 节点的ExecStart后面      "
    echo " -H tcp://0.0.0.0:2376 -H unix:///var/run/docker.sock --tlsverify --tlscacert=$CERT_DIR/ca.pem --tlscert=$CERT_DIR/server-cert.pem --tlskey=$CERT_DIR/server-key.pem"
    echo ""
    echo " 更新配置：systemctl daemon-reload"
    echo " 重启docker：systemctl restart docker"
    echo " 查看是否启动成功：systemctl status docker"
    echo ""
    echo "######################################################################"
    echo ""
    echo "要从远程客户端连接，你需要以下文件 (位于 $CERT_DIR 目录):"
    echo "  - CA 证书: ca.pem"
    echo "  - 客户端证书: cert.pem"
    echo "  - 客户端私钥: key.pem"
    echo ""
    echo "远程连接命令示例 (需将证书文件复制到客户端):"
    echo "  docker --tlsverify --tlscacert=ca.pem --tlscert=cert.pem --tlskey=key.pem -H=$SERVER_IP:2376 version"
    echo ""
    echo "！！！重要防火墙提示！！！"
    echo "请确保防火墙允许 TCP 端口 2376 的入站连接或。"
    echo "例如，使用 firewalld:"
    echo "  sudo firewall-cmd --permanent --add-port=2376/tcp"
    echo "  sudo firewall-cmd --reload"
else
    echo "Docker 未启用 TLS 远程连接，仅监听在本地 Unix 套接字 unix:///var/run/docker.sock。"
    echo "  docker ps"
fi
echo ""
echo "使用 'docker info | grep -E 'TLS|Hosts|Docker Root Dir|Registry Mirrors|Server Version\"' 查看详细配置。"