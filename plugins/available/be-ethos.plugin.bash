cite about-plugin
about-plugin 'behancecompute ethos ssh and node listing helper'

function __be-ethos-usage {
    echo -e "Usage: be-ethos <tier> <command>"
    echo -e "  <tier>: dev | stage | prod"
    echo -e "  <command>: ssh <ip|hosttype> | ls [<search_string>] | scpkey"
    echo -e "    ssh <ip|hosttype>: ssh to specific ip or first node of the hosttype ('control'/'worker'/'proxy'/'bastion')"
    echo -e "    ls [<search_string>]: list instances with optional search string"
    echo -e "    scpkey: copy required key to bastion host"
    echo -e "\nDescription: Does nice things with ec2 and behancecompute, uses jungle, ~/.aws/<tier>.sh, cloudops-be-app-<tier>.pem keys and virtualenv 'be-ethos'"
    echo -e "\nExample: be-ethos dev ssh control"
    echo -e "\nAvailable environnment variables:"
    echo -e "  BE_ETHOS_PRODUCT_NAME: default is 'behanceco'"
    echo -e "  BE_ETHOS_VIRTUALENV_NAME: set to your preferred virtualenv name, or \"NO\" to not use virtualenv, if not specified it will use the 'be-ethos' virtualenv"
    echo -e "  BE_ETHOS_AUTO_LS: set to \"NO\" to turn off automatically ls'ing nodes after commands"
}

function be-ethos {
  if [[ "$BE_ETHOS_PRODUCT_NAME" == "" ]] ; then
    BE_ETHOS_PRODUCT_NAME="behanceco"
  fi
  HOST_IP=""
  LOCALUSER_KEY_PATH_PREFIX="${HOME}/.ssh/cloudops-beh-app-" # path and prefix to dev/stage/prod cloudops keys 
  REMOTEUSER_NAME="core"
  # set BE_ETHOS_VIRTUALENV_NAME env variable to "NO" to turn off, or set to your own preferred virtualenv
  if [[ "$BE_ETHOS_VIRTUALENV_NAME" != "NO" && "$BE_ETHOS_VIRTUALENV_NAME" == "" ]]; then
    BE_ETHOS_VIRTUALENV_NAME="be-ethos" # set to "NO" to turn off
  fi
  AWS_SOURCE_ROOT="${HOME}/.aws" #set to "" to turn off aws source scripting for credentials
  if [[ "$1" == "" || "$2" == "" ]]; then
    if [[ "$1" != "" ]] ; then
      echo "Missing required parameters"
    fi
    __be-ethos-usage
    return 0
  elif [[ "$1" == "dev" || "$1" == "stage" || "$1" == "prod" ]]; then
    ENVIRON="$1"
  else
    echo "Environment $1 not supported"
    __be-ethos-usage
    return 1
  fi
  LOCALUSER_KEY_PATH="${LOCALUSER_KEY_PATH_PREFIX}${ENVIRON}.pem"
  REMOTEUSER_KEY_NAME="cloudops-beh-app-${ENVIRON}.pem"
  REMOTEUSER_KEY_PATH="/home/${REMOTEUSER_NAME}/.ssh/${REMOTEUSER_KEY_NAME}"
  if [[ "$AWS_SOURCE_ROOT" != "" ]] ; then 
    source ${AWS_SOURCE_ROOT}/${ENVIRON}.sh
  fi
  if [[ "$BE_ETHOS_VIRTUALENV_NAME" != "NO" ]] ; then
    workon $BE_ETHOS_VIRTUALENV_NAME
    WORKON_CODE="$?"
    if [[ "$WORKON_CODE" == "1" ]] ; then
      echo "virtualenv $BE_ETHOS_VIRTUALENV_NAME doesn't exist, creating..."
      mkvirtualenv $BE_ETHOS_VIRTUALENV_NAME
    elif [[ "$WORKON_CODE" == "127" ]] ; then
      echo "virtualenv command not installed, set BE_ETHOS_VIRTUALENV_NAME to \"\" to not see this message / disable virtualenv"
    elif [[ "$WORKON_CODE" != "0" ]] ; then
      echo "There was a problem with the $BE_ETHOS_VIRTUALENV_NAME virtualenv, confirm it's ok"
      return 1
    fi
  fi
  if [[ "$(jungle ec2 > /dev/null; echo $?)" != "0" ]] ; then
    echo "There was a problem with jungle, confirm jungle is installed"
    return 1
  fi

  JUNGLE_MAIN_QUERY="$(jungle ec2 ls "${BE_ETHOS_PRODUCT_NAME}*" | grep -v 'terminated' | sort )"
  HOST_JUNGLE_BASTION="$(echo "$JUNGLE_MAIN_QUERY" | head -1 | grep 'bastion')"
  HOST_IP_BASTION="$(echo "$HOST_JUNGLE_BASTION" | awk '{print $5}')"
  HOST_NAME_BASTION="$(echo "$HOST_JUNGLE_BASTION" | awk '{print $1}')"

  if [[ "$2" == "ssh" ]]; then

    if [[ "$BE_ETHOS_AUTO_LS" != "NO" ]] ; then 
      echo -e "$JUNGLE_MAIN_QUERY\n"
    fi
    if [[ $3 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        HOST_IP="$3"
        HOST_TYPE=""
        echo "IP: $HOST_IP"
    else
        HOST_TYPE="$3"
        HOST_IP=""
        echo "hosttype: $HOST_TYPE"
    fi

    if [[ "$4" != "" ]] ; then
      SSH_CMD="$4"
    else
      SSH_CMD=""
    fi
    if [[ "$HOST_TYPE" == "bastion" || "$HOST_IP" == "$HOST_IP_BASTION" ]]; then
      if [[ "$SSH_CMD" == "" ]] ; then
        echo -e "Connecting to bastion host $HOST_NAME_BASTION at $HOST_IP_BASTION\n"
        ssh -i ${LOCALUSER_KEY_PATH} ${REMOTEUSER_NAME}@${HOST_IP_BASTION}
      else
        echo -e "Running cmd: \"$SSH_CMD\" on bastion host $HOST_NAME_BASTION at $HOST_IP_BASTION\n"
        ssh -i ${LOCALUSER_KEY_PATH} ${REMOTEUSER_NAME}@${HOST_IP_BASTION} /bin/bash << EOF
        $SSH_CMD
EOF
      fi
    elif [[ "$HOST_TYPE" != "" || "$HOST_IP" != "" ]] ; then
      if [[ "$HOST_IP" == "" ]] ; then
        GREP_QUERY="$HOST_TYPE"
      else
        GREP_QUERY="$HOST_IP"
      fi
      HOST_IP="$(echo "$JUNGLE_MAIN_QUERY" | grep "$GREP_QUERY" | head -1 | awk '{print $4}')"
      HOST_NAME="$(echo "$JUNGLE_MAIN_QUERY" | grep "$GREP_QUERY" | head -1 | awk '{print $1}')"
      if [[ "$SSH_CMD" == "" ]] ; then
        echo -e "Connecting to [$HOST_NAME @ $HOST_IP]\n  (thru bastion host [$HOST_NAME_BASTION @ $HOST_IP_BASTION ])...\n"
        ssh -i ${LOCALUSER_KEY_PATH} -At ${REMOTEUSER_NAME}@${HOST_IP_BASTION} ssh -oStrictHostKeyChecking=no -i ${REMOTEUSER_KEY_PATH} -At ${REMOTEUSER_NAME}@${HOST_IP}
      else
        echo -e "Running \"$SSH_CMD\" on [$HOST_NAME @ $HOST_IP]\n  (thru bastion host [$HOST_NAME_BASTION @ $HOST_IP_BASTION ])...\n"
        ssh -i ${LOCALUSER_KEY_PATH} -AT ${REMOTEUSER_NAME}@${HOST_IP_BASTION} ssh -oStrictHostKeyChecking=no -i ${REMOTEUSER_KEY_PATH} -AT ${REMOTEUSER_NAME}@${HOST_IP} /bin/bash << EOF
        $SSH_CMD
EOF
      fi
    else # HOST_TYPE and HOST_IP are blank
      echo "Host not found"
      return 1
    fi
  elif [[ "$2" == "ls" ]]; then
    if [[ "$3" == "" ]]; then
      echo "$JUNGLE_MAIN_QUERY"
    else
      echo "$JUNGLE_MAIN_QUERY" | grep "$3"
    fi

  elif [[ "$2" == "scpkey" ]]; then
    echo "Copying cloudops key to new bastion host..."
    scp -i ${LOCALUSER_KEY_PATH} ${LOCALUSER_KEY_PATH} ${REMOTEUSER_NAME}@${HOST_IP_BASTION}:${REMOTEUSER_KEY_PATH}

  else
    echo "Command not recognized: $2"
    __be-ethos-usage
  fi
}
