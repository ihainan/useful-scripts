#!/usr/bin/env bash

set -e

# Usage: fcp spark4@hostname:/home/mlzdev/imlhome/spark4/configuration/keystore.jks .
# Usage: fcp fcp.sh spark4@hostname:/home/mlzdev/imlhome/spark4/configuration

die() {
  echo "[FATAL] $1" >&2 && exit 1
}

dbg() {
  if [[ -n "$DEBUG" ]]; then
    echo "[DEBUG] $1"
  fi
}

show_help() {
  echo_in_green "Usage: "
  echo "  fcp [flags] <from_path> <destination_path>"
  echo_in_green "Flags: "
  echo "  -a: Use ASCII transfer type instead of binary."
  echo "  -r: Recursive mode; copy whole directory trees."
  echo_in_green "Examples: "
  echo "  fcp spark4@hostname:/home/mlzdev/imlhome/spark4/configuration/keystore.jks ."
  echo "  fcp -a fcp.sh spark4@hostname:/home/mlzdev/imlhome/spark4/configuration"
}

split_remote_path() {
  local full_path="$1"
  local username="$(echo $full_path) | cut -d@ -f1"
  local username="$(echo $full_path) | cut -d@ -f1"
  local username="$(echo $full_path) | cut -d@ -f1"
}

NARGS=-1

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ==============================================================================
# Function    : Echo text in green
# Arguments:
#   Text
# ==============================================================================
echo_in_green() {
  echo -e "${GREEN}$1${NC}"
}

# ==============================================================================
# Function    : Echo text in blue
# Arguments:
#   Text
# ==============================================================================
echo_in_blue() {
  echo -e "${BLUE}$1${NC}"
}

while [[ "$#" -ne "$NARGS" ]]; do
  NARGS=$#
  case $1 in
  # SWITCHES
  -h | --help) # This help message
    show_help
    exit 1
    ;;
  -v | --version) # Enable verbose messages
    shift && echo "$version"
    exit 1
    ;;
  -a)
    shift
    FLAG_ASCII_MODE="true"
    flag_ascii="-a"
    ;;
  -r)
    shift
    FLAG_RECUSIVE_MODE="true"
    flag_recusive="-R"
    ;;
  *)
    if [[ -z "$PATH_FROM" ]]; then
      if [[ $# != 0 ]]; then
        PATH_FROM="$1"
        dbg "PATH_FROM = $PATH_FROM"
        shift
      fi
    elif [[ -z "$PATH_TO" ]]; then
      if [[ $# != 0 ]]; then
        PATH_TO="$1"
        dbg "PATH_TO = $PATH_TO"
        shift
      fi
    fi
    ;;
  esac
done

if [[ -z "$PATH_FROM" || -z "$PATH_TO" ]]; then
  show_help && exit 1
fi

if [[ "$PATH_FROM" == *"@"* && "$PATH_FROM" == *":"* ]]; then
  echo "Fetching file from remote server to local file system."
  # spark4@hostname:/home/mlzdev/imlhome/spark4/configuration/keystore.jks
  remote_username="$(echo $PATH_FROM | cut -d@ -f1)"
  remote_host="$(echo $PATH_FROM | cut -d@ -f2 | cut -d: -f1)"
  remote_path="$(echo $PATH_FROM | cut -d@ -f2 | cut -d: -f2)"
  dbg "remote_username = $remote_username"
  dbg "remote_host = $remote_host"
  dbg "remote_path = $remote_path"

  read -s -p "Input password for $remote_username@$remote_host: " remote_password
  echo ""
  ncftpget $flag_recusive $flag_ascii -u "$remote_username"  -p "$remote_password" "$remote_host" "$PATH_TO" "$remote_path"
else
  echo "Uploading file from local file system to remote server."
  # spark4@hostname:/home/mlzdev/imlhome/spark4/configuration/keystore.jks
  remote_username="$(echo $PATH_TO | cut -d@ -f1)"
  remote_host="$(echo $PATH_TO | cut -d@ -f2 | cut -d: -f1)"
  remote_path="$(echo $PATH_TO | cut -d@ -f2 | cut -d: -f2)"
  dbg "remote_username = $remote_username"
  dbg "remote_host = $remote_host"
  dbg "remote_path = $remote_path"

  read -s -p "Input password for $remote_username@$remote_host: " remote_password
  echo ""
  ncftpput $flag_recusive $flag_ascii -u "$remote_username"  -p "$remote_password" "$remote_host"  "$remote_path" "$PATH_FROM"
fi
