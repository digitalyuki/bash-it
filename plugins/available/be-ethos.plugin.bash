cite about-plugin
about-plugin 'behancecompute ethos ssh and node listing helper'

function __be-ethos-usage {
    echo -e "Usage: be-ethos <tier> <command> [<ip|hosttype>]"
    echo -e "  <tier>: dev | stage | prod"
    echo -e "  <command>: ssh | ls | scpkey (ssh will ssh to server, ls will list instances, scpkey will copy required key to bastion host)"
    echo -e "  [ip|hosttype]: Optional, jumps to specific IP or first node listed of that type, like '10.10.10.10' or 'control', if not specified jumps to bastion host"
    echo -e "Description: Does nice things with ec2 and behancecompute, uses jungle, ~/.aws/<tier>.sh and virtualenv 'aws' (you can turn that off that check, see VIRTUALENV_NAME variable)"
    echo -e "Example: be-ethos dev ssh control"
}

function be-ethos {
  HOST_IP=""
  PRODUCT_NAME="behanceco"
  LOCALUSER_KEY_PATH_PREFIX="${HOME}/.ssh/cloudops-beh-app-" # path and prefix to dev/stage/prod cloudops keys 
  REMOTEUSER_NAME="core"
  VIRTUALENV_NAME="aws" # set to "" to turn off virtualenv
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
  if [[ "$VIRTUALENV_NAME" != "" ]] ; then
    if [[ "$(workon $VIRTUALENV_NAME ; echo $? )" != "0" ]]; then
      echo "There was a problem with the 'aws' virtualenv, confirm it's ok"
      return 1
    fi
    workon $VIRTUALENV_NAME
  fi
  if [[ "$(jungle ec2 > /dev/null; echo $?)" != "0" ]] ; then
    echo "There was a problem with jungle, confirm jungle is installed"
    return 1
  fi

  if [[ "$2" == "ssh" ]]; then
    jungle ec2 ls "${PRODUCT_NAME}*" | sort ; echo ""

    if [[ "$3" == "" ]] ; then
      HOST_NAME='bastion'
    else
      if [[ $3 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          HOST_IP="$3"
          echo "IP found: $HOST_IP"
      else
          HOST_NAME="$3"
          echo "hostname found: $HOST_NAME"
      fi
    fi

    HOST_IP_BASTION="$(jungle ec2 ls "${PRODUCT_NAME}*bastion*" | awk '{print $5}')"
    HOST_NAME_BASTION="$(jungle ec2 ls "${PRODUCT_NAME}*bastion*" | awk '{print $1}')"

    if [[ "$HOST_NAME" == "bastion" || "$HOST_IP" == "$HOST_IP_BASTION" ]]; then
      echo -e "Connecting to bastion host $HOST_NAME_BASTION at $HOST_IP_BASTION\n"
      ssh -i ${LOCALUSER_KEY_PATH} ${REMOTEUSER_NAME}@${HOST_IP_BASTION}
    elif [[ "$HOST_NAME" == "" && "$HOST_IP" == "" ]]; then
      echo "Host not found"
      return 1
    else
      if [[ "$HOST_IP" == "" ]] ; then
        HOST_IP="$(jungle ec2 ls "${PRODUCT_NAME}*${HOST_NAME}*" | sort | head -1 | awk '{print $4}')"
        HOST_NAME="IP"
      fi
      echo -e "Connecting to [$HOST_NAME @ $HOST_IP] from the bastion host [$HOST_NAME_BASTION @ $HOST_IP_BASTION ]...\n"
      ssh -i ${LOCALUSER_KEY_PATH} -At ${REMOTEUSER_NAME}@${HOST_IP_BASTION} ssh -i ${REMOTEUSER_KEY_PATH} -At ${REMOTEUSER_NAME}@${HOST_IP}
    fi

  elif [[ "$2" == "ls" ]]; then
    if [[ "$3" == "" ]]; then
      jungle ec2 ls "${PRODUCT_NAME}*" | sort
    else
      jungle ec2 ls "${PRODUCT_NAME}*${3}*" | sort
    fi

  elif [[ "$2" == "scpkey" ]]; then
    echo "Copying cloudops key to new bastion host..."
    HOST_IP_BASTION="$(jungle ec2 ls "${PRODUCT_NAME}*bastion*" | awk '{print $5}')"
    HOST_NAME_BASTION="$(jungle ec2 ls "${PRODUCT_NAME}*bastion*" | awk '{print $1}')"
    scp -i ${LOCALUSER_KEY_PATH} ${LOCALUSER_KEY_PATH} ${REMOTEUSER_NAME}@${HOST_IP_BASTION}:${REMOTEUSER_KEY_PATH}

  else
    echo "Command not recognized: $2"
    __be-ethos-usage
  fi
}

