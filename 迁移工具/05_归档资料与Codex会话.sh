#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="/home/isee-cdh/松灵小车"
CODEX_DIR="/home/isee-cdh/.codex"
OUTPUT_PARENT="${SOURCE_DIR}/迁移输出"
ARCHIVE_NAME="Ranger-VLM_Nav_aux_last_session_20261008"
STAGING_DIR="${OUTPUT_PARENT}/${ARCHIVE_NAME}"
ARCHIVE_FILE="${OUTPUT_PARENT}/${ARCHIVE_NAME}.tar.zst"

mkdir -p "${STAGING_DIR}/资料/松灵小车"
mkdir -p "${STAGING_DIR}/Codex会话"
chmod 700 "${STAGING_DIR}" "${STAGING_DIR}/Codex会话"

rsync -a \
  --exclude='/迁移输出/' \
  --exclude='/APIkey.txt' \
  --exclude='/matterport api token.txt' \
  "${SOURCE_DIR}/" "${STAGING_DIR}/资料/松灵小车/"

# 只处理归档副本，不修改旧电脑原文件。
while IFS= read -r -d '' text_file; do
  sed -E -i 's/sk-[A-Za-z0-9_-]{12,}/<REDACTED_API_KEY>/g' "${text_file}"
done < <(find "${STAGING_DIR}/资料/松灵小车" -type f \
  \( -name '*.md' -o -name '*.txt' -o -name '*.sh' -o -name '*.yaml' -o -name '*.json' \) \
  -print0)

cp "${SOURCE_DIR}/迁移情况清单_20261008.md" "${STAGING_DIR}/迁移情况清单.md"

SESSION_MANIFEST="${STAGING_DIR}/Codex会话清单.tsv"
printf 'timestamp\tcwd\tsession_id\trelative_path\tsize_bytes\tsha256\n' >"${SESSION_MANIFEST}"

latest_session_file=""
latest_session_time=""
latest_session_cwd=""
latest_session_id=""
while IFS= read -r -d '' session_file; do
  meta_line="$(head -n 1 "${session_file}")"
  session_cwd="$(jq -r 'select(.type=="session_meta") | .payload.cwd // empty' <<<"${meta_line}")"
  session_time="$(jq -r 'select(.type=="session_meta") | .payload.timestamp // .timestamp // empty' <<<"${meta_line}")"
  session_id="$(jq -r 'select(.type=="session_meta") | .payload.id // .payload.session_id // empty' <<<"${meta_line}")"
  thread_source="$(jq -r 'select(.type=="session_meta") | .payload.thread_source // empty' <<<"${meta_line}")"

  if [[ "${session_cwd}" != /home/isee-cdh/ws* || "${thread_source}" != user ]]; then
    continue
  fi
  if [[ -n "${session_time}" && "${session_time}" > "${latest_session_time}" ]]; then
    latest_session_file="${session_file}"
    latest_session_time="${session_time}"
    latest_session_cwd="${session_cwd}"
    latest_session_id="${session_id}"
  fi
done < <(find "${CODEX_DIR}/sessions" "${CODEX_DIR}/archived_sessions" \
  -type f -name '*.jsonl' -print0 2>/dev/null)

if [[ -z "${latest_session_file}" ]]; then
  echo "错误：未找到 /home/isee-cdh/ws 下的 Codex 主会话" >&2
  exit 1
fi

relative_path="${latest_session_file#${CODEX_DIR}/}"
destination="${STAGING_DIR}/Codex会话/${relative_path}"
mkdir -p "$(dirname "${destination}")"
install -m 600 "${latest_session_file}" "${destination}"
file_size="$(stat -c %s "${destination}")"
file_sha="$(sha256sum "${destination}" | awk '{print $1}')"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "${latest_session_time}" "${latest_session_cwd}" "${latest_session_id}" \
  "${relative_path}" "${file_size}" "${file_sha}" >>"${SESSION_MANIFEST}"

chmod 600 "${SESSION_MANIFEST}"
printf 'Codex sessions: 1\nCodex bytes: %d\n' "${file_size}"

find "${STAGING_DIR}" -type d -exec chmod go-rwx {} +
find "${STAGING_DIR}" -type f -exec chmod go-rwx {} +

tar --zstd -cf "${ARCHIVE_FILE}" -C "${OUTPUT_PARENT}" "${ARCHIVE_NAME}"
chmod 600 "${ARCHIVE_FILE}"
sha256sum "${ARCHIVE_FILE}"
