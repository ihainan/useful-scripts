# useful-scripts

## vps-init.sh

Used to set up my Linux VPS, tested on Ubuntu 18.04 server, usage: `./vps-init.sh <USER_NAME> <USER_PASSWORD>`.

- Install essential softwares (zsh, git, curl, screen, etc.).
- Create a new user and setup Oh My Zsh for it.
- Install and set up ShadowSocks server (random password).
- Enable BBR for KVM or OpenVZ.
- Install and set up [frp server](https://github.com/fatedier/frp) (random password).
- Install and configure Samba (Save files in /var/local/samba).
- Install and configure Aria2 / Aria2NG.

## better-shanbay.js

A [TamperMonkey](https://www.tampermonkey.net/) JavaScript which can make your Shanbay better.

- Automatically expand all the definitions of a word.
- Switch to community contributing notes if there's no your own note.
- Pronounce words in the review page one by one.

## Evernote Hightlight

A [TamperMonkey](https://www.tampermonkey.net/) JavaScript used to highlight the selected text on Evernote Web App.
