command -v curl >/dev/null
command -v jq >/dev/null
command -v wget >/dev/null

: "${IOS_DEVICE_ID:?Missing IOS_DEVICE_ID}"

TITLE_ID="${TITLE_ID:-20ca2}"
SCID="${SCID:-4fc10100-5f7a-4470-899b-280835760c07}"
BASE_URL="https://${TITLE_ID}.playfabapi.com"
COUNT="${COUNT:-300}"

ROOT_DIR="$(pwd)"
STATE_DIR="${ROOT_DIR}/.state"
DATA_DIR="${ROOT_DIR}/data"
SITE_DIR="${ROOT_DIR}/site"
TMP_DIR="${ROOT_DIR}/.tmp_build"

mkdir -p "${STATE_DIR}" "${DATA_DIR}" "${SITE_DIR}" "${TMP_DIR}"
