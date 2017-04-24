#!/usr/bin/env bash

set -eu -o pipefail
BASE_PATH="$(readlink -f $(dirname ${0}))"

function usage {
  printf "######## USAGE ########\n" >&2
  printf "You have two options to run this script:\n\n" >&2
  printf "Option 1: providing a Dockerfile to check if you use an up to date base image\n" >&2
  printf "\t ${0} --dockerfile=<path to dockerfile> [--user=<registry username>] [--pass=<registry password>]\n\n" >&2
  printf "Option 2: providing a 'FROM' string to check if you use an up to date image\n" >&2
  printf "\t ${0} --from=<alpine:3.5> [--user=<registry username>] [--pass=<registry password>]\n\n" >&2
  printf "If do not provide --user and/or --pass the script tries to take it from the environment.\n" >&2
  printf "You then need to 'export REPOSITORY_USER=<registry username>' and 'export REPOSITORY_TOKEN=<registry password>'\n" >&2
  printf "The username and password are only required if you either use a private registry or a private hub.docker.com repository.\n\n" >&2

  if [ -n "${1}" ]; then
    printf "${1}\n\n" >&2
  fi

  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dockerfile=*)
      DOCKERFILE="${1#*=}"

      DOCKERFILE_BASE_PATH="$(readlink -f $(dirname ${DOCKERFILE}))"
      DOCKERFILE_BASE_NAME="$(basename ${DOCKERFILE})"

      if [ ! -f ${DOCKERFILE_BASE_PATH}/${DOCKERFILE_BASE_NAME} ]; then
        usage "Location of '${DOCKERFILE_BASE_PATH}/${DOCKERFILE_BASE_NAME}' is not valid."
      fi

      IMAGE_FROM="$(grep -oP 'FROM[ ]+\K.*' ${DOCKERFILE_BASE_PATH}/${DOCKERFILE_BASE_NAME})"
      ;;
    --from=*)
      IMAGE_FROM="${1#*=}"
      ;;
    --user=*)
      REPOSITORY_USER="${1#*=}"
      ;;
    --pass=*)
      REPOSITORY_TOKEN="${1#*=}"
      ;;
    *)
      usage
  esac

  shift
done

REPOSITORY_USER=${REPOSITORY_USER:-}
REPOSITORY_TOKEN=${REPOSITORY_TOKEN:-}
IS_PRIVATE_REGISTRY=$(echo "${IMAGE_FROM}" | grep -oqP '^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+(:[0-9]+)?' && echo 1 || echo 0)

if [ ${IS_PRIVATE_REGISTRY} -eq 1 ]; then
  if [ -z "${REPOSITORY_USER}" -o -z "${REPOSITORY_TOKEN}" ]; then
    usage "For a private registry you need to provide a username and password like:\n\t${0} --user=<registry username> --pass=<registry password>"
  fi
fi

if [ ${IS_PRIVATE_REGISTRY} -eq 1 ]; then
  REGISTRY_HOST="$(echo "${IMAGE_FROM}" | grep -oP '^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+(:[0-9]+)?')"
  REPOSITORY_NAME="$(echo "${IMAGE_FROM}" | grep -oP '^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+(:[0-9]+)?\K.*' | awk -F':' '{print $1}' | sed 's/^\///')"
  IMAGE_VERSION="$(echo "${IMAGE_FROM}" | grep -oP '^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9](?:\.[a-zA-Z]{2,})+(:[0-9]+)?\K.*' | awk -F':' '{print $2}')"
  IS_SHA="$(echo ${IMAGE_VERSION} | grep -oqP '([0-9a-f]{6})([0-9a-f]{1,34})' && echo 1 || echo 0)"
else
  REGISTRY_HOST="registry.hub.docker.com"
  REPOSITORY_NAME="$([ $(echo "${IMAGE_FROM}" | grep -c ':') -gt 0 ] && echo "${IMAGE_FROM}" | awk -F':' '{print $1}' || echo "${IMAGE_FROM}")"
  IMAGE_VERSION="$([ $(echo "${IMAGE_FROM}" | grep -c ':') -gt 0 ] && echo "${IMAGE_FROM}" | awk -F':' '{print $2}' || echo latest)"
  IS_SHA=0
fi

printf "Processing '${REGISTRY_HOST}/${REPOSITORY_NAME}:${IMAGE_VERSION}'\n\n"

if [[ ${IMAGE_VERSION} = 'latest' ]]; then
  printf 'You are using the "latest" tag as upstream for '${REGISTRY_HOST}/${REPOSITORY_NAME}'. Please consider using semantic versioning @see: https://developers.redhat.com/blog/2016/02/24/10-things-to-avoid-in-docker-containers/\n\n'
  exit 0
fi

IS_V2_REGISTRY=$([ $(echo "${REPOSITORY_NAME}" | grep -c '/') -gt 0 ] && echo 1 || echo 0)

if [ ${IS_V2_REGISTRY} -eq 1 ]; then
  REPOSITORY_AUTHENTICATE="$(curl -sI https://${REGISTRY_HOST}/v2/${REPOSITORY_NAME}/tags/list | grep -i www-authenticate)"
  REPOSITORY_AUTHENTICATE_METHOD="$(echo ${REPOSITORY_AUTHENTICATE} | awk '{print $2}')"
  REPOSITORY_AUTHENTICATE_REALM="$(echo ${REPOSITORY_AUTHENTICATE} | grep -oP 'realm="\K[^"]+')"
  REPOSITORY_AUTHENTICATE_SERVICE="$(echo ${REPOSITORY_AUTHENTICATE} | grep -oP 'service="\K[^"]+')"
  REPOSITORY_AUTHENTICATE_SCOPE="$(echo ${REPOSITORY_AUTHENTICATE} | grep -oP 'scope="\K[^"]+')"

  if [ ${IS_PRIVATE_REGISTRY} -eq 1 ]; then
    REPOSITORY_BEARER="$(curl -s -u ${REPOSITORY_USER}:${REPOSITORY_TOKEN} "${REPOSITORY_AUTHENTICATE_REALM}?service=${REPOSITORY_AUTHENTICATE_SERVICE}&scope=${REPOSITORY_AUTHENTICATE_SCOPE}" | jq -r .token)"
  else
    REPOSITORY_BEARER="$(curl -s "${REPOSITORY_AUTHENTICATE_REALM}?service=${REPOSITORY_AUTHENTICATE_SERVICE}&scope=${REPOSITORY_AUTHENTICATE_SCOPE}" | jq -r .token)"
  fi

  REPOSITORY_TAGS=$(curl -s -H "Authorization: ${REPOSITORY_AUTHENTICATE_METHOD} ${REPOSITORY_BEARER}" "https://${REGISTRY_HOST}/v2/${REPOSITORY_NAME}/tags/list" | jq -r '.tags | .[]')
else
  REPOSITORY_TAGS=$(curl -s "https://${REGISTRY_HOST}/v1/repositories/${REPOSITORY_NAME}/tags" | jq -r '.[].name')
fi

if [ ${IS_SHA} -eq 1 ]; then
  LATEST_REPOSITORY_TAG=$(echo "${REPOSITORY_TAGS}" | tail -n1)
  LEVENSHTEIN_DISTANCE=$(awk -f ${BASE_PATH}/levenshtein.awk ${IMAGE_VERSION} ${LATEST_REPOSITORY_TAG} | grep -ioP '^levenshtein distance: \K[0-9]+')

  if [ ${LEVENSHTEIN_DISTANCE} -ne 0 ]; then
    printf "A newer image for '${REGISTRY_HOST}/${REPOSITORY_NAME}' is available.\nCurrently you are on ${IMAGE_VERSION}. The latest available image is ${LATEST_REPOSITORY_TAG}.\n\n"
    exit 2
  else
    printf "You are using the latest available image for '${REGISTRY_HOST}/${REPOSITORY_NAME}'.\n\n"
  fi
else
  LEVENSHTEIN_PREFIXED_TAGS=""

  for REPOSITORY_TAG in $(echo ${REPOSITORY_TAGS} | grep -oP "${IMAGE_VERSION} \K.*" | sed 's/ /\n/g'); do
    LEVENSHTEIN_DISTANCE=$(awk -f ${BASE_PATH}/levenshtein.awk ${IMAGE_VERSION} ${REPOSITORY_TAG} | grep -ioP '^levenshtein distance: \K[0-9]+')

    if [ ${LEVENSHTEIN_DISTANCE} -gt 5 ]; then
      continue
    elif [ ${LEVENSHTEIN_DISTANCE} -eq 0 ]; then
      continue
    fi

    LEVENSHTEIN_PREFIXED_TAGS="${LEVENSHTEIN_PREFIXED_TAGS} ${LEVENSHTEIN_DISTANCE}___${REPOSITORY_TAG}"
  done

  LEVENSHTEIN_PREFIXED_TAGS=$(echo ${LEVENSHTEIN_PREFIXED_TAGS} | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed 's/ /\n/g' | sort)

  if [ $(echo -n "${LEVENSHTEIN_PREFIXED_TAGS}" | wc -l) -gt 1 ]; then
    printf "Your image for '${REGISTRY_HOST}/${REPOSITORY_NAME}' seems out of date. Several newer images are available (ordered by build date and levenshtein distance):\n"

    for NEW_TAG in ${LEVENSHTEIN_PREFIXED_TAGS}; do
      printf "\t'${REGISTRY_HOST}/${REPOSITORY_NAME}:$(echo ${NEW_TAG} | sed 's/[0-9]___//')'\n"
    done

    printf "\n"
    exit 2
  elif [ $(echo -n "${LEVENSHTEIN_PREFIXED_TAGS}" | wc -l) -eq 1 ]; then
    LATEST_REPOSITORY_TAG=$(echo "${LEVENSHTEIN_PREFIXED_TAGS}" | tail -n1 | sed 's/[0-9]___//')
    printf "A newer image for '${REGISTRY_HOST}/${REPOSITORY_NAME}' is available.\nCurrently you are on ${IMAGE_VERSION}. The latest available image is ${LATEST_REPOSITORY_TAG}.\n\n"
    exit 2
  fi

  printf "You are using the latest available image for '${REGISTRY_HOST}/${REPOSITORY_NAME}'.\n\n"
fi
