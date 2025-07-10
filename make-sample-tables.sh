#!/bin/bash
set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SCRIPT_DIR

# load environment variables from .env
if [ -e "$SCRIPT_DIR"/.env ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR"/.env
else
  echo 'Environment file .env not found. Therefore, dotenv.sample will be used.'
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR"/dotenv.sample
fi

# health check
docker inspect -f '{{.State.Status}}' "$ORACLE_CONTAINER_NAME" | grep running
if [[ $? != 0 ]]; then
  echo -e "\n\033[36mContainer $ORACLE_CONTAINER_NAME is not running\033[0m"
  exit 1
fi

docker inspect -f '{{.State.Health.Status}}' "$ORACLE_CONTAINER_NAME" | grep healthy
if [[ $? != 0 ]]; then
  echo -e "\n\033[36mContainer $ORACLE_CONTAINER_NAME is not healty\033[0m"
  exit 1
fi

check="$(which sqlplus)"
if [[ $? != 0 ]]; then
  echo -e "\n\033[36mSQL*Plus not found\033[0m"
  exit 1
fi

check="$(which sqlldr)"
if [[ $? != 0 ]]; then
  echo -e "\n\033[36mSQL Loader not found\033[0m"
  exit 1
fi

cd ./oracle/sample_lob_data

sqlplus -s PDBUSER/"$ORACLE_PWD"@//localhost:"$ORACLE_LISTENER_PORT"/"$ORACLE_PDB" @create_table.sql
if [[ $? != 0 ]]; then
  echo -e "\n\033[36mCreate Table error\033[0m"
  exit 1
fi

sqlldr PDBUSER/"$ORACLE_PWD"@//localhost:"$ORACLE_LISTENER_PORT"/"$ORACLE_PDB"  CONTROL=t_lob_header.ctl LOG=t_lob_header.log