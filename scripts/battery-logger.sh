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

read_bool_from_online_devices() {
  local supply_dir
  local supply_type
  local online_value

  shopt -s nullglob
  for supply_dir in "${POWER_SUPPLY_DIR}"/*; do
    [[ -d "${supply_dir}" ]] || continue
    [[ -r "${supply_dir}/online" ]] || continue

    supply_type=""
    if [[ -r "${supply_dir}/type" ]]; then
      supply_type="$(<"${supply_dir}/type")"
    fi
    if [[ "${supply_type}" == "Battery" ]]; then
      continue
    fi

    online_value="$(tr -dc '0-9' < "${supply_dir}/online")"
    if [[ -n "${online_value}" ]] && (( online_value > 0 )); then
      shopt -u nullglob
      echo "true"
      return 0
    fi
  done

  shopt -u nullglob
  echo "false"
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

ac_on="$(read_bool_from_online_devices)"
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

tmp_file="$(mktemp "${LOG_FILE}.tmp.XXXXXX")"
trap 'rm -f "${tmp_file}"' EXIT

jq --arg data "${date_value}" --argjson level "${level}" --argjson charging "${charging}" --argjson ac_on "${ac_on}" \
  '. + [{"data": $data, "level": $level, "charging": $charging, "ac_on": $ac_on}]' \
  "${LOG_FILE}" > "${tmp_file}"

chmod 0644 "${tmp_file}"
mv "${tmp_file}" "${LOG_FILE}"
trap - EXIT
