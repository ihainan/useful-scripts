#!/usr/bin/env bash

function add_new_user() {
    echo "Creating user ${USERNAME}..."

    # Create user and change password
    SALT="Q9"
    HASH=$(perl -e "print crypt(${PASSWORD},${SALT})")
    [[ ! -d /home/${USERNAME} ]] && useradd -m -d /home/${USERNAME} -s /bin/bash ${USERNAME} && usermod --password ${HASH} ${USERNAME}

    # Update sudo file
    grep -q "${USERNAME}" /etc/sudoers || echo "${USERNAME}	ALL=(ALL:ALL) ALL" >> /etc/sudoers

    echo "User $USERNAME was created."
}

function install_softwares() {
    echo "Installing softwares..."
    apt-get update
    apt-get -y install git vim python-pip openjdk-8-jdk wget screen curl lsof
    echo "All softwares were installed."
}

function config_shadowsocks() {
    echo "Configuring ShadowSocks..."

    # Install Shadowsocks
    pip install shadowsocks

    # Replace OpenSSL cleanup method
    set +e
    ssl_version=$(openssl version -v | cut -d ' ' -f 2)
    first_num=$(echo ${ssl_version} | cut -d '.' -f 1)
    second_num=$(echo ${ssl_version} | cut -d '.' -f 2)
    if [[ "$first_num" -ge "1" ]] && [[ "$second_num" -ge "1" ]]; then
        echo "Updating /usr/local/lib/python2.7/dist-packages/shadowsocks/crypto/openssl.py"
        sed -i -e 's/cleanup/reset/g' /usr/local/lib/python2.7/dist-packages/shadowsocks/crypto/openssl.py
    fi
    set -e

    # Create configuration file
    export SS_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
        cat <<EOT > /etc/shadowsocks.json
{
    "server":"0.0.0.0",
    "server_port":9528,
    "local_address": "127.0.0.1",
    "local_port":1080,
    "password":"${SS_PASSWORD}",
    "timeout":600,
    "method":"aes-256-cfb",
    "fast_open": true
}
EOT

    # Add auto start
    if [[ ! -f /etc/systemd/system/shadowsocks.service ]]; then
        cat <<EOT >> /etc/systemd/system/shadowsocks.service
[Unit]
Description=Shadowsocks Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks.json

[Install]
WantedBy=multi-user.target
EOT
        systemctl enable shadowsocks.service
        systemctl start shadowsocks.service
    fi
    echo "Shadowsocks has been brought up."
}

function enable_bbr_openvz() {
    # Download rinetd
    mkdir -p /root/tools/rinetd
    cd /root/tools/rinetd & wget --no-check-certificate https://raw.githubusercontent.com/mixool/rinetd/master/rinetd_bbr_powered -O /root/tools/rinetd/rinetd
    chmod a+x /root/tools/rinetd/rinetd

    # Configurate rinetd
    cat <<EOT > /etc/rinetd.conf
# bindadress bindport connectaddress connectport
0.0.0.0 443 0.0.0.0 443
0.0.0.0 80 0.0.0.0 80
0.0.0.0 9527 0.0.0.0 9527
EOT

    cat <<EOT > /etc/systemd/system/rinetd.service
[Unit]
Description=rinetd

[Service]
ExecStart=/root/tools/rinetd/rinetd -f -c /etc/rinetd.conf raw venet0:0
Restart=always

[Install]
WantedBy=multi-user.target
EOT
    systemctl enable rinetd.service && systemctl start rinetd.service
}


function enable_bbr_kvm() {
    set +e
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf
    exit_status=$?
    if [[ ! $exit_status -eq 0 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        sysctl net.ipv4.tcp_available_congestion_control
        sysctl net.ipv4.tcp_congestion_control
    fi
    set -e
}

function enable_bbr() {
    echo "Enabling BBR..."

    # Determine the type of VM virtualization technology
    apt-get install -y virt-what
    if [[ "$(virt-what)" == "openvz" ]]; then
        echo "OpenVZ..."
        enable_bbr_openvz
    else
        echo "KVM..."
        enable_bbr_kvm
    fi

    echo "Successfully enabled BBR."
}

function setup_zsh() {
    # chsh without password
    echo "Seting up Zsh..."

    # Install zsh
    apt-get -y install zsh

    # Update /etc/pam.d/chsh file to allow change shell without password
    sed -i -e 's/auth       required   pam_shells.so/auth       sufficient   pam_shells.so/g' /etc/pam.d/chsh

    # Install oh my zsh as $USERNAME
    if [[ ! -d /home/${USERNAME}/.oh-my-zsh ]]; then
        su $USERNAME -c "cd ~; $(curl -fsSL http://iij.ihainan.me/tools/install.sh)"
    fi

    echo "Oh My Zsh has been configured."
}

function setup_frp() {
    echo "Seting up frp server..."

    if [[ ! -d /root/tools/frp_0.27.0_linux_amd64 ]]; then
        # Download frp
        cd /root && mkdir -p tools/ && cd tools
        wget https://github.com/fatedier/frp/releases/download/v0.27.0/frp_0.27.0_linux_amd64.tar.gz && tar -zxvf frp_0.27.0_linux_amd64.tar.gz

        # Create configuration file
        export FRP_PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)
        cat <<EOT > /etc/frps.ini
[common]
bind_port = 3400
vhost_http_port = 3401
dashboard_port = 3402
dashboard_user = $USERNAME
dashboard_pwd = $FRP_PASSWORD
auto_token = $FRP_PASSWORD
EOT

        # Create & enable frp service
        if [[ ! -f /etc/systemd/system/frps.service ]]; then
            cat <<EOT >> /etc/systemd/system/frps.service
[Unit]
Description=FRP server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/root/tools/frp_0.27.0_linux_amd64/frps -c /etc/frps.ini

[Install]
WantedBy=multi-user.target
EOT
            systemctl enable frps.service
            systemctl start frps.service
        fi
    fi
    echo "frp server has been installed."
}

function setup_samba() {
    echo "Seting up Samba server..."

    # Install Samba
    apt-get -y install samba

    # Configure Samba
    SAMBA_DIR="/var/local/samba"
    SAMBA_CONF="/etc/samba/smb.conf "

    mkdir -p $SAMBA_DIR
    chmod -R a+rwx $SAMBA_DIR
    set +e
    grep -q "media_samba" $SAMBA_CONF
    exit_status=$?
    if [[ ! $exit_status -eq 0 ]]; then
        cp $SAMBA_CONF $SAMBA_CONF.bak
        cat <<EOT >> $SAMBA_CONF
[media_samba]

path = $SAMBA_DIR
browsable = yes
writable = yes
read only = no
force user = $USERNAME
EOT

        # Add new user
        (echo $PASSWORD; echo $PASSWORD) | smbpasswd -a $USERNAME -s
    fi
    set -e
    echo "Samba has been installed."
}

function setup_aria2() {
    echo "Seting up Aria2..."

    # Install Aria2 & apache2 & unzip
    apt-get -y install aria2 apache2 unzip

    # Configure Aria2
    if [[ ! -f /etc/aria2/aria2.conf ]]; then
        mkdir -p $SAMBA_DIR
        chmod -R a+rwx $SAMBA_DIR
        mkdir -p /etc/aria2/
        touch /etc/aria2/aria2.session
        cat <<EOT >> /etc/aria2/aria2.conf
# Creat by FS

## 下载设置 ##

# 断点续传
continue=true
# 最大同时下载任务数，运行时可修改，默认：5
max-concurrent-downloads=10
# 单个任务最大线程数，添加时可指定，默认：5
split=16
# 最小文件分片大小，添加时可指定，取值范围 1M -1024M, 默认：20M
# 假定 size=10M, 文件为 20MiB 则使用两个来源下载；文件为 15MiB 则使用一个来源下载
min-split-size=1M
# 同一服务器连接数，添加时可指定，默认：1
max-connection-per-server=16
# 断开速度过慢的连接
lowest-speed-limit=0
# 整体下载速度限制，运行时可修改，默认：0
#max-overall-download-limit=0
# 单个任务下载速度限制，默认：0
#max-download-limit=0
# 整体上传速度限制，运行时可修改，默认：0
#max-overall-upload-limit=0
# 单个任务上传速度限制，默认：0
#max-upload-limit=0
# 禁用 IPv6, 默认:false
#disable-ipv6=true
# 当服务器返回 503 错误时，aria2 会尝试重连
# 尝试重连次数，0 代表无限，默认：5
max-tries=0
# 重连冷却，默认：0
#retry-wait=0

## 进度保存相关 ##

# 从会话文件中读取下载任务
# 开启该参数后 aria2 将只接受 session 中的任务，这意味着 aria2 一旦使用 conf 后将不再接受来自终端的任务，所以该条只需要在启动 rpc 时加上就可以了
input-file=/etc/aria2/aria2.session
# 在 Aria2 退出时保存 `错误 / 未完成` 的下载任务到会话文件
save-session=/etc/aria2/aria2.session
# 定时保存会话，0 为退出时才保存，需 1.16.1 以上版本，默认：0
save-session-interval=60
# 强制保存会话，即使任务已经完成，默认:false
# 较新的版本开启后会在任务完成后依然保留.aria2 文件
#force-save=false

## RPC 相关设置 ##

# 启用 RPC, 默认:false
enable-rpc=true
# 允许所有来源，默认:false
rpc-allow-origin-all=true
# 允许非外部访问，默认:false
rpc-listen-all=true
# 事件轮询方式，取值:[epoll, kqueue, port, poll, select], 不同系统默认值不同
# event-poll=kqueue
# RPC 监听端口，端口被占用时可以修改，默认：6800
#rpc-listen-port=6800
# 设置的 RPC 授权令牌，v1.18.4 新增功能，取代 --rpc-user 和 --rpc-passwd 选项
rpc-secret=$PASSWORD

## BT/PT 下载相关 ##

# 当下载的是一个种子 (以.torrent 结尾) 时，自动开始 BT 任务，默认:true
#follow-torrent=true
# BT 监听端口，当端口被屏蔽时使用，默认：6881-6999
#listen-port=51413
# 单个种子最大连接数，默认：55
#bt-max-peers=55
# 打开 DHT 功能，PT 需要禁用，默认:true
#enable-dht=false
# 打开 IPv6 DHT 功能，PT 需要禁用，默认:true
#enable-dht6=false
# DHT 网络监听端口，默认：6881-6999
#dht-listen-port=6881-6999
# 本地节点查找，PT 需要禁用，默认:false
bt-enable-lpd=true
# 种子交换，PT 需要禁用，默认:true
#enable-peer-exchange=true
# 每个种子限速，对少种的 PT 很有用，默认：50K
#bt-request-peer-speed-limit=50K
# 客户端伪装，PT 需要
#peer-id-prefix=-TR2770-
#user-agent=Transmission/2.77
# 当种子的分享率达到这个数时，自动停止做种，0 为一直做种，默认：1.0
#seed-ratio=0
# BT 校验相关，默认:true
#bt-hash-check-seed=true
# 继续之前的 BT 任务时，无需再次校验，默认:false
bt-seed-unverified=true
# 保存磁力链接元数据为种子文件 (.torrent 文件), 默认:false
bt-save-metadata=true
# 强制加密，防迅雷必备
#bt-require-crypto=true

## 磁盘相关 ##

#文件保存路径，默认为当前启动位置
dir=$SAMBA_DIR
#另一种 Linux 文件缓存方式，使用前确保您使用的内核支持此选项，需要 1.15 及以上版本 (?)
enable-mmap=true
# 文件预分配方式，能有效降低磁盘碎片，默认:prealloc
# 预分配所需时间：快 none < trunc < falloc < prealloc 慢
# falloc 仅仅比 trunc 慢 0.06s
# 磁盘碎片：无 falloc = prealloc < trunc = none 有
# 推荐优先级：高 falloc --> prealloc --> trunc -->none 低
# EXT4, btrfs, xfs, NTFS 等新型文件系统建议使用 falloc, falloc (fallocate) 在这些文件系统上可以瞬间创建完整的空文件
# trunc (ftruncate) 同样是是瞬间创建文件，但是与 falloc 的区别是创建出的空文件不占用实际磁盘空间
# prealloc 传统的创建完整的空文件，aria2 会一直等待直到分配结束，也就是说如果是在 HHD 上下载 10G 文件，那么你的 aria2 将会一直等待你的硬盘持续满载工作直到 10G 文件创建完成后才会开始下载
# none 将不会预分配，磁盘碎片程度受下面的 disk-cache 影响，trunc too
# 请勿在传统文件系统如：EXT3, FAT32 上使用 falloc, 它的实际效果将与 prealloc 相同
# MacOS 建议使用 prealloc, 因为它不支持 falloc, 也不支持 trunc, but 可以尝试用 brew 安装 truncate 以支持 trunc (ftruncate)
# 事实上我有些不能理解 trunc 在 aria2 中的角色，它与 none 几乎没有区别，也就是说：太鸡肋了
 file-allocation=trunc
# 启用磁盘缓存，0 为禁用缓存，需 1.16 以上版本，默认：16M
disk-cache=64M
EOT

    # Create aria2 service
        if [[ ! -f /etc/systemd/system/aria2.service ]]; then
            cat <<EOT >> /etc/systemd/system/aria2.service
[Unit]
Description=Aria2 server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/aria2c --conf-path=/etc/aria2/aria2.conf

[Install]
WantedBy=multi-user.target
EOT
            systemctl enable aria2.service
            systemctl start aria2.service
        fi

        # Download and setup Aria2NG
        wget -c https://github.com/mayswind/AriaNg/releases/download/1.1.0/AriaNg-1.1.0.zip
        mkdir -p /var/www/html/aria2
        unzip AriaNg-1.1.0.zip -d /var/www/html/aria2
    fi

    echo "Aria2 has been installed."
}

function byeMessage() {
    echo "ShadowSocks password = $SS_PASSWORD"
    echo "frp password = $FRP_PASSWORD"
}

set -e

if [[ "$#" -ne "2" ]]; then
    echo "Usage: $0 <USER_NAME> <USER_PASSWORD>"
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"

add_new_user
install_softwares
config_shadowsocks
enable_bbr
setup_zsh
setup_frp
setup_samba
setup_aria2
byeMessage