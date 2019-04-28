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
    apt-get -y install zsh git vim python-pip openjdk-8-jdk wget screen curl lsof
    echo "All softwares were installed."
}

function config_shadowsocks() {
    echo "Configuring ShadowSocks..."
    
    # Install Shadowsocks
    pip install shadowsocks
    sed -i -e 's/cleanup/reset/g' /usr/local/lib/python2.7/dist-packages/shadowsocks/crypto/openssl.py
    
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

function enable_bbr() {
    echo "Enabling BBR..."
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
    echo "Successfully enabled BBR."
}

function setupZSH() {
    # chsh without password
    echo "Seting up Zsh..."
    
    # Update /etc/pam.d/chsh file to allow change shell without password
    sed -i -e 's/auth       required   pam_shells.so/auth       sufficient   pam_shells.so/g' /etc/pam.d/chsh
    
    # Install oh my zsh as $USERNAME
    if [[ ! -d /home/${USERNAME}/.oh-my-zsh ]]; then
        su $USERNAME -c "cd ~; $(curl -fsSL http://iij.ihainan.me/tools/install.sh)"
    fi
    
    echo "Oh My Zsh has been configured."
}

function setupFRP() {
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
setupZSH
setupFRP
byeMessage
