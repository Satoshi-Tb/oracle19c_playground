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

sqlplus -s PDBUSER/"$ORACLE_PWD"@//localhost:"$ORACLE_LISTENER_PORT"/"$ORACLE_PDB" @./oracle/sample_plsql/add_lob_detail.sql
if [[ $? != 0 ]]; then
  echo -e "\n\033[36merror\033[0m"
  exit 1
fi

sqlplus -s PDBUSER/"$ORACLE_PWD"@//localhost:"$ORACLE_LISTENER_PORT"/"$ORACLE_PDB" @./oracle/sample_type/sample_list_type.sql
if [[ $? != 0 ]]; then
  echo -e "\n\033[36merror\033[0m"
  exit 1
fi

sqlplus -s PDBUSER/"$ORACLE_PWD"@//localhost:"$ORACLE_LISTENER_PORT"/"$ORACLE_PDB" @./oracle/sample_plsql/insert_sample_list.sql
if [[ $? != 0 ]]; then
  echo -e "\n\033[36merror\033[0m"
  exit 1
fi

