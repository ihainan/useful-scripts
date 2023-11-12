#!/usr/bin/env bash

function add_new_user() {
  echo "Creating user ${USERNAME}..."

  if [[ ! -d /home/${USERNAME} ]]; then
    # Create user and change password
    SALT="Q9"
    HASH=$(perl -e "print crypt(${PASSWORD},${SALT})")
    [[ ! -d /home/${USERNAME} ]] && useradd -m -d /home/"${USERNAME}" -s /bin/bash "${USERNAME}" && usermod --password "${HASH}" "${USERNAME}"

    # Update sudo file
    grep -q "${USERNAME}" /etc/sudoers || echo "${USERNAME}	ALL=(ALL:ALL) ALL" >>/etc/sudoers

    echo "User $USERNAME was created."
  else
    echo "User $USERNAME already exists"
  fi
}

function install_software() {
  echo "Installing software..."
  apt-get update
  # python3-pip
  apt-get -y install git vim openjdk-11-jdk wget screen curl lsof build-essential nginx uuid-runtime
  echo "All software were installed."
}

function setup_zsh() {
  echo "Setting up Oh my zsh..."

  if [[ ! -d "/home/$USERNAME/.oh-my-zsh" ]]; then
    # Install zsh
    apt-get -y install zsh

    # Update /etc/pam.d/chsh file to allow change shell without password
    sed -i -e 's/auth       required   pam_shells.so/auth       sufficient   pam_shells.so/g' /etc/pam.d/chsh

    # Install oh my zsh as $USERNAME
    if [[ ! -d /home/${USERNAME}/.oh-my-zsh ]]; then
      # see https://github.com/ohmyzsh/ohmyzsh/issues/11092 for more details
      su "$USERNAME" -c "chsh -s $(which zsh)"
      su "$USERNAME" -c "curl https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /home/$USERNAME/install.sh"
      su "$USERNAME" -c "sed -i 's/CHSH=no/CHSH=yes/g' /home/$USERNAME/install.sh"
      su "$USERNAME" -c "cd ~ && echo Y | sh /home/$USERNAME/install.sh"

      # How to uninstall oh my zsh: https://askubuntu.com/questions/963874/uninstall-oh-my-zsh
    fi
  else
    echo "Oh My ZSH already exists"
  fi

  echo "Oh My Zsh was configured."
}

function setup_frp() {
  echo "Setting up frp server..."

  if [[ ! -d /root/tools/frp_0.27.0_linux_amd64 ]]; then
    # Download frp
    cd /root && mkdir -p tools/ && cd tools
    wget https://github.com/fatedier/frp/releases/download/v0.27.0/frp_0.27.0_linux_amd64.tar.gz && tar -zxvf frp_0.27.0_linux_amd64.tar.gz
  else
    echo "frp already installed"
  fi

  if [[ ! -f "/etc/frps.ini" ]]; then
    # Create configuration file
    export FRP_PASSWORD=$(
      date +%s | sha256sum | base64 | head -c 32
      echo
    )
    cat <<EOT >/etc/frps.ini
[common]
bind_port = 3400
vhost_http_port = $USERNAME
dashboard_port = 3402
dashboard_user = ihainan
dashboard_pwd = $FRP_PASSWORD
token = $FRP_PASSWORD
authentication_method = token
EOT
  else
    echo "/etc/frps.ini already exists"
  fi

  # Create & enable frp service
  if [[ ! -f /etc/systemd/system/frps.service ]]; then
    cat <<EOT >>/etc/systemd/system/frps.service
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
  else
    echo "frps.service already exists"
  fi
  echo "frp server has been installed."
}

function install_docker() {
  echo "Setting up Docker CE..."

  if ! command -v docker >/dev/null 2>&1; then
    set +e
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg --yes; done
    set -e

    # Install docker
    # https://docs.docker.com/install/linux/docker-ce/ubuntu/
    # Add Docker's official GPG key:
    apt-get update
    apt-get install ca-certificates curl gnupg --yes
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources:
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" |
      tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin --yes
  else
    echo "Docker already installed."
  fi

  # Allow non-root user
  if ! grep -q -E "^docker:" /etc/group; then
    groupadd docker
    usermod -a -G docker "$USERNAME"
  fi

  echo "Docker CE has been installed."
}

function install_v2ray() {
  if [[ ! -f /usr/local/etc/v2ray/config.json ]]; then
    uuid=$(uuidgen)
    echo "UUID $uuid generated"

    mkdir -p /usr/local/etc/v2ray/
    cat <<EOT >/usr/local/etc/v2ray/config.json
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/ray"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOT
    echo "/usr/local/etc/v2ray/config.json generated"
  else
    echo "/usr/local/etc/v2ray/config.json already exists"
  fi

  if docker ps | grep -q v2fly/v2fly-core 2>&1 >/dev/null; then
    echo "Docker container is running"
  else
    echo "Starting docker container"
    docker run -d --name v2ray -v /usr/local/etc/v2ray/config.json:/etc/v2ray/config.json -p 10086:10086 v2fly/v2fly-core run -c /etc/v2ray/config.json
  fi

  if ! grep -q "start-v2ray" "/home/$USERNAME/.zshrc"; then
    echo "Updating ~/.zshrc to add v2ray aliases..."
    cat <<EOT >>"/home/$USERNAME/.zshrc"
alias start-v2ray='docker start v2ray'
alias stop-v2ray='docker stop v2ray'
alias check-v2ray='docker logs v2ray'
alias restart-v2ray='docker restart v2ray'
alias v2ray-config='sudo cat /usr/local/etc/v2ray/config.json'
EOT
    echo '.zshrc updated.'
  fi
}

function config_certbot_zsh() {
  echo "Installing Snap & Certbot"
  if ! command -v snap >/dev/null 2>&1; then
    apt update
    apt install snapd --yes
    snap install core
    snap refresh core
    echo "Snap installed"
  else
    echo "Snap already installed"
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    echo 'y' | snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
  else
    echo "certbot already installed"
  fi

  if ! grep -q "certbot-wildcard" "/home/$USERNAME/.zshrc"; then
    cat <<EOT >>"/home/$USERNAME/.zshrc"
alias certbot-wildcard='sudo certbot certonly --manual --manual-public-ip-logging-ok --preferred-challenges dns-01 --server https://acme-v02.api.letsencrypt.org/directory -d '
EOT
  fi
}

function byeMessage() {
  echo "BYE"
}

set -e

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
  echo "Please run this script as root"
  exit
fi

if [[ "$#" -ne "2" ]]; then
  echo "Usage: $0 <USER_NAME> <USER_PASSWORD>"
  exit 1
fi

USERNAME="$1"
PASSWORD="$2"

add_new_user
install_software
setup_zsh
install_docker
install_v2ray
config_certbot_zsh
setup_frp
byeMessage
