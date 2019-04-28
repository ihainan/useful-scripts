# useful-scripts

## vps-init.sh

Used to set up my Linux VPS, tested on Ubuntu 18.04 server, usage: `./vps-init.sh <USER_NAME> <USER_PASSWORD>`.

- Install essential softwares (zsh, git, curl, screen, etc.).
- Create a new user and setup Oh My Zsh for it.
- Install and set up ShadowSocks server (random password).
- Enable BBR.
- Install and set up [frp server](https://github.com/fatedier/frp) (random password).