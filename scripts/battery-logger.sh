#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${BATTERY_LOG_FILE:-/var/log/battery-log.json}"
LOCK_FILE="${BATTERY_LOG_LOCK_FILE:-/run/battery-log.lock}"
POWER_SUPPLY_DIR="${BATTERY_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
BATTERY_DEVICE_NAME="${BATTERY_DEVICE_NAME:-}"

find_capacity_file() {
  local battery_dir
  local battery_type

  shopt -s nullglob
  if [[ -n "${BATTERY_DEVICE_NAME}" ]]; then
    for battery_dir in "${POWER_SUPPLY_DIR}"/${BATTERY_DEVICE_NAME}; do
      [[ -d "${battery_dir}" ]] || continue
      if [[ -r "${battery_dir}/capacity" ]]; then
        if [[ -r "${battery_dir}/type" ]]; then
          battery_type="$(<"${battery_dir}/type")"
          if [[ "${battery_type}" != "Battery" ]]; then
            continue
          fi
        fi

        echo "${battery_dir}/capacity"
        shopt -u nullglob
        return 0
      fi
    done
  else
    for battery_dir in "${POWER_SUPPLY_DIR}"/*; do
      [[ -d "${battery_dir}" ]] || continue
      if [[ -r "${battery_dir}/capacity" ]]; then
        if [[ -r "${battery_dir}/type" ]]; then
          battery_type="$(<"${battery_dir}/type")"
          if [[ "${battery_type}" != "Battery" ]]; then
            continue
          fi
        fi

        echo "${battery_dir}/capacity"
        shopt -u nullglob
        return 0
      fi
    done
  fi

  shopt -u nullglob
  return 1
}

capacity_file="$(find_capacity_file || true)"
if [[ -z "${capacity_file}" ]]; then
  if [[ -n "${BATTERY_DEVICE_NAME}" ]]; then
    echo "battery-logger: no battery found at ${POWER_SUPPLY_DIR}/${BATTERY_DEVICE_NAME}/capacity" >&2
  else
    echo "battery-logger: no battery found with capacity under ${POWER_SUPPLY_DIR}" >&2
  fi
  exit 1
fi

battery_dir="$(dirname "${capacity_file}")"

level="$(tr -dc '0-9' < "${capacity_file}")"
if [[ -z "${level}" ]] || (( level < 0 || level > 100 )); then
  echo "battery-logger: invalid capacity value: ${level:-<empty>}" >&2
  exit 1
fi

charging="false"
if [[ -r "${battery_dir}/status" ]]; then
  status_value="$(<"${battery_dir}/status")"
  if [[ "${status_value}" == "Charging" ]]; then
    charging="true"
  fi
fi

date_value="$(date --iso-8601=seconds)"

mkdir -p "$(dirname "${LOG_FILE}")"
mkdir -p "$(dirname "${LOCK_FILE}")"
touch "${LOG_FILE}"

exec 9> "${LOCK_FILE}"
flock -x 9

if [[ ! -s "${LOG_FILE}" ]]; then
  printf '[]\n' > "${LOG_FILE}"
fi
chmod 0644 "${LOG_FILE}"

last_level="$(jq -r 'if type == "array" and length > 0 then .[-1].level // "" else "" end | tostring' "${LOG_FILE}")"
last_charging="$(jq -r 'if type == "array" and length > 0 then (.[-1].charging | if . == null then "" else tostring end) else "" end' "${LOG_FILE}")"
if [[ "${last_level}" == "${level}" ]] && [[ "${last_charging}" == "${charging}" ]]; then
  exit 0
fi

tmp_file="$(mktemp "${LOG_FILE}.tmp.XXXXXX")"
trap 'rm -f "${tmp_file}"' EXIT

jq --arg date "${date_value}" --arg level "${level}" --argjson charging "${charging}" \
  '. + [{"date": $date, "level": $level, "charging": $charging}]' \
  "${LOG_FILE}" > "${tmp_file}"

chmod 0644 "${tmp_file}"
mv "${tmp_file}" "${LOG_FILE}"
trap - EXIT
