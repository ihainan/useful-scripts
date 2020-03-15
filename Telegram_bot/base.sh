#!/bin/bash
#
# Basic library functions for a Telegram Bot program

#######################################
# Output message to stderr
# Arguments:
#   None
# Outputs:
#   Writes all the arguments and parameters to stderr
#######################################
err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Send message ${text} to chat ${chat_id} using token ${bot_token}
# Arguments:
#   bot_token
#   chat_id
#   text
#######################################
send_text_message() {
  bot_token="$1"
  chat_id="$2"
  text="$3"
  retry=3
  while [[ ${retry} -gt 0 ]]; do
    # send send_message request to the Telegram server
    set +e
    echo "Sending message, retry = ${retry}"
    curl --request POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
      --connect-timeout 2 \
      --header 'Content-Type: application/json' \
      --data-raw "{
	\"chat_id\": \"${chat_id}\",
	\"text\": \"${text}\"
}"
    status=$?
    set -e
    if [[ ${status} -eq 0 ]]; then
      break
    else
      retry=$(($retry - 1))
    fi
  done

  # check if succeeded to send message
  if [[ $retry -eq 0 ]]; then
    err "Failed to send message to the Telegram server, chat_id = ${chat_id}, text = ${text}"
    return 1
  fi
}

#######################################
# Run command ${cmd} and send the result to chat ${chat_id} using token ${bot_token}
# Arguments:
#   cmd
#   bot's token
#   chat's ID
#######################################
run_command_and_send_result() {
  all_args=("$@")
  bot_token="$1"
  chat_id="$2"
  cmd=("${all_args[@]:2}")

  # run command
  set +e
  cmd_output="$(${cmd} 2>&1)"
  cmd_status=$?
  echo "cmd result = ${cmd_output} ${cmd_status}"

  # send message
  if [[ $cmd_status -eq 0 ]]; then
    send_text_message "${bot_token}" "${chat_id}" "${cmd_output}"
  else
    send_text_message "${bot_token}" "${chat_id}" "[ERROR][${cmd_status}] ${cmd_output}"
  fi
  msg_status=$?
  set -e

  # check if succeeded to run command and send message
  if [[ $msg_status -ne 0 ]]; then
    err "Failed to send message, chat_id = ${chat_id}, text = ${text}, cmd_status = ${cmd_status}"
    return 1
  fi
}

#######################################
# Check if program exists in the $PATH
# Arguments:
#   program name
#######################################
cmd_exists() {
  set +e
  if cmd -v "$1" 2>$1 >/dev/null; then
    set -e
    return 0
  else
    set -e
    return 1
  fi
}
