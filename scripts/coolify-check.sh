#!/usr/bin/env bash
# =============================================================================
# scripts/coolify-check.sh
#
# Verifica que el/los compose del kit cumplen el contrato de Coolify:
#   Punto 1 — sin puertos publicados, container_name, privileged, cap_add,
#             devices, network_mode/pid/ipc host, security_opt unconfined,
#             binds fuera del repo ni docker.sock (en servicios sin profiles).
#   Punto 2 — sin `name:` fijo a nivel raíz ni en redes o volúmenes; Coolify
#             pone el nombre del proyecto y de los volúmenes.
#
# Uso: bash scripts/coolify-check.sh
# Salida 0 = cumple. Distinto de 0 = enumera las violaciones como
# `servicio: motivo` por línea.
#
# Por cada `${VAR}` del compose genera un valor ficticio no secreto. Las
# variables cuyo nombre contiene URL, ENDPOINT u HOST reciben
# `https://ejemplo.invalid`; el resto, un placeholder literal. No se usa
# ningún valor real de `.env`.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${COOLIFY_CHECK_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# Cada entrada del contrato: "<compose_relpath>|<base_dir_relpath>". El
# base_dir es la raíz del proyecto compose; si está vacío se usa REPO_ROOT.
# Hoy solo hay una app: ia-trazas. Se puede sobreescribir la lista con la
# variable de entorno COOLIFY_CHECK_TARGETS (separadas por coma) para
# reutilizar este script en pruebas con composes arbitrarios.
if [[ -n "${COOLIFY_CHECK_TARGETS:-}" ]]; then
  IFS=',' read -ra APPS <<<"${COOLIFY_CHECK_TARGETS}"
else
  APPS=(
    "compose.yaml|"
  )
fi

FAILS=0
TMP_ENV=""
TMP_COMPOSE_OUT=""

cleanup() {
  if [[ -n "${TMP_ENV}" && -f "${TMP_ENV}" ]]; then
    rm -f "${TMP_ENV}"
  fi
  if [[ -n "${TMP_COMPOSE_OUT}" && -f "${TMP_COMPOSE_OUT}" ]]; then
    rm -f "${TMP_COMPOSE_OUT}"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

# Devuelve todas las variables ${VAR} declaradas en un compose (con o sin
# default, requerido o no), una por línea, sin duplicados.
vars_in_file() {
  local file="$1"
  grep -oE '\$\{[A-Z_][A-Z0-9_]*' "${file}" \
    | sed -E 's/^\$\{//' \
    | sort -u
}

# Decide el placeholder para una variable según su nombre.
# Variables con URL/ENDPOINT/HOST reciben un host inválido; el resto, un
# literal no secreto.
placeholder_for() {
  local var="$1"
  case "${var}" in
    *URL*|*ENDPOINT*|*HOST*) echo "https://ejemplo.invalid" ;;
    *)                       echo "x1234567890abcdef"       ;;
  esac
}

fail() {
  echo "  fail: $1" >&2
  FAILS=$((FAILS+1))
}

# Imprime una línea "red <k>: name fijo (línea N)" o
# "volumen <k>: name fijo (línea N)" por cada recurso de los bloques
# `networks:` o `volumes:` de la RAIZ que declare `name:` como hijo directo.
# Ignora `name:` en environment, labels, x-*, driver_opts y demás.
fixed_resource_names() {
  awk '
    /^[[:space:]]*(#.*)?$/ { next }
    /^[^[:space:]]/ {
      kind = ""; rind = -1; cind = -1
      if ($0 ~ /^networks:[[:space:]]*(#.*)?$/) kind = "red"
      if ($0 ~ /^volumes:[[:space:]]*(#.*)?$/)  kind = "volumen"
      next
    }
    kind == "" { next }
    {
      match($0, /^[[:space:]]*/); ind = RLENGTH
      if (rind < 0 || ind <= rind) {
        rind = ind; cind = -1; key = $1; sub(/:.*$/, "", key); next
      }
      if (cind < 0) cind = ind
      if (ind == cind && $0 ~ /^[[:space:]]*name[[:space:]]*:/) {
        printf "%s %s: name fijo (línea %d)\n", kind, key, NR
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Comprobaciones por compose
# ---------------------------------------------------------------------------

check_compose() {
  local compose_rel="$1"
  local base_dir_rel="${2:-}"
  local compose_path="${REPO_ROOT}/${compose_rel}"
  local base_dir_path="${REPO_ROOT}"
  if [[ -n "${base_dir_rel}" ]]; then
    base_dir_path="${REPO_ROOT}/${base_dir_rel}"
  fi

  echo "→ ${compose_rel}"

  if [[ ! -f "${compose_path}" ]]; then
    fail "no se encontró ${compose_rel}"
    return
  fi

  # --- 1. Generar .env temporal con placeholders ----------------------------
  TMP_ENV="$(mktemp -t coolify-check.XXXXXX.env)"
  while IFS= read -r var; do
    [[ -z "${var}" ]] && continue
    printf '%s=%s\n' "${var}" "$(placeholder_for "${var}")" >> "${TMP_ENV}"
  done < <(vars_in_file "${compose_path}")

  # --- 2. Renderizar con docker compose ------------------------------------
  # El JSON va a stdout; cualquier warning o error de docker va a stderr y
  # se descarta mientras el comando termine 0. Si falla, se imprime abajo.
  TMP_COMPOSE_OUT="$(mktemp -t coolify-check.XXXXXX.json)"
  local compose_stderr
  compose_stderr="$(mktemp -t coolify-check.XXXXXX.err)"
  if ! docker compose \
        --project-directory "${base_dir_path}" \
        -f "${compose_path}" \
        --env-file "${TMP_ENV}" \
        config --format json > "${TMP_COMPOSE_OUT}" 2> "${compose_stderr}"
  then
    fail "docker compose config no renderiza"
    sed 's/^/    /' "${compose_stderr}" >&2
    rm -f "${compose_stderr}"
    return
  fi
  rm -f "${compose_stderr}"

  # --- 3. Contrato punto 2: name: fijo --------------------------------------
  # El render de docker compose siempre rellena `name` en redes y volúmenes
  # (auto = `${project}_${key}`); por eso el contrato se valida contra el
  # ARCHIVO FUENTE: cualquier `name:` declarado explícitamente rompe el
  # contrato porque fija el nombre que Coolify quiere asignar.
  # 3a. A nivel raíz: fija el nombre del proyecto.
  if grep -E '^name:' "${compose_path}" >/dev/null 2>&1; then
    fail "compose tiene 'name:' fijo a nivel raíz"
  fi

  # 3b. En los bloques `networks:` y `volumes:` de la raíz: un `name:` hijo
  # directo de un recurso fija el nombre que Coolify quiere asignar.
  local fixed_names
  fixed_names="$(fixed_resource_names "${compose_path}")"
  if [[ -n "${fixed_names}" ]]; then
    while IFS= read -r l; do
      [[ -z "${l}" ]] && continue
      fail "${l}"
    done <<<"${fixed_names}"
  fi

  # --- 4. Contrato punto 1: por cada servicio sin profiles ------------------
  local svc_keys
  svc_keys="$(jq -r '.services // {} | keys[]' "${TMP_COMPOSE_OUT}" 2>/dev/null || true)"
  if [[ -z "${svc_keys}" ]]; then
    fail "no hay servicios en el compose renderizado"
    return
  fi

  while IFS= read -r svc; do
    [[ -z "${svc}" ]] && continue

    # 4a. services con `profiles` se excluyen del contrato.
    local prof_count
    prof_count="$(jq -r --arg s "${svc}" '(.services[$s].profiles // []) | length' "${TMP_COMPOSE_OUT}" 2>/dev/null || echo 0)"
    if [[ "${prof_count}" != "0" ]]; then
      continue
    fi

    # 4b. ports
    if jq -e --arg s "${svc}" '.services[$s] | has("ports")' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: publica puertos"
    fi

    # 4c. container_name
    if jq -e --arg s "${svc}" '.services[$s] | has("container_name")' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: usa container_name fijo"
    fi

    # 4d. privileged
    if jq -e --arg s "${svc}" '.services[$s].privileged == true' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: privileged=true"
    fi

    # 4e. cap_add
    if jq -e --arg s "${svc}" '.services[$s] | has("cap_add")' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: usa cap_add"
    fi

    # 4f. devices
    if jq -e --arg s "${svc}" '.services[$s] | has("devices")' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: usa devices"
    fi

    # 4g. network_mode host
    if jq -e --arg s "${svc}" '.services[$s].network_mode == "host"' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: network_mode=host"
    fi

    # 4h. pid host
    if jq -e --arg s "${svc}" '.services[$s].pid == "host"' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: pid=host"
    fi

    # 4i. ipc host
    if jq -e --arg s "${svc}" '.services[$s].ipc == "host"' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: ipc=host"
    fi

    # 4j. security_opt con unconfined o label:disable/label=disable.
    #
    # Docker y Compose aceptan tanto `clave:valor` como `clave=valor`.
    # Ademas de seccomp/apparmor, la forma label:disable desactiva las
    # MAC labels del contenedor. Cualquier cadena que matchee
    # "unconfined" o "label[:=]disable" rompe el aislamiento.
    if jq -e --arg s "${svc}" '
        (.services[$s].security_opt // [])
        | any(test("unconfined|label[:=]disable"))
      ' "${TMP_COMPOSE_OUT}" >/dev/null 2>&1; then
      fail "${svc}: security_opt con unconfined o label[:=]disable"
    fi

    # 4k. binds fuera del repo o docker.sock.
    #
    # `docker compose config` resuelve los binds relativos a rutas
    # absolutas (${base_dir}/algo), así que filtrar por "starts with /"
    # marca como violación cualquier bind legítimo dentro del repo. La
    # regla real es: docker.sock, o un bind que NO esté dentro de
    # ${base_dir}.
    local bind_violations
    bind_violations="$(jq -r --arg s "${svc}" --arg root "${base_dir_path}" '
        (.services[$s].volumes // [])
        | .[]
        | select(type == "object" and has("source"))
        | select(.type == "bind")
        | select((.source | test("docker\\.sock")) or ((.source | startswith($root + "/")) | not) and .source != $root)
        | .source
      ' "${TMP_COMPOSE_OUT}" 2>/dev/null || true)"
    if [[ -n "${bind_violations}" ]]; then
      while IFS= read -r b; do
        [[ -z "${b}" ]] && continue
        fail "${svc}: bind fuera del repo o docker.sock (${b})"
      done <<<"${bind_violations}"
    fi
  done <<<"${svc_keys}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

for entry in "${APPS[@]}"; do
  IFS='|' read -r compose_rel base_dir_rel <<<"${entry}"
  check_compose "${compose_rel}" "${base_dir_rel}"
done

echo
if (( FAILS > 0 )); then
  echo "FAIL: ${FAILS} violación(es) del contrato Coolify" >&2
  exit 1
fi
echo "OK: contrato Coolify cumplido"
exit 0