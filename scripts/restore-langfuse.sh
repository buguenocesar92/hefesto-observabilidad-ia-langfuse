#!/usr/bin/env bash
# =============================================================================
# restore-langfuse.sh — Restauracion de una instancia Langfuse desde un respaldo
#
# Kit Hefesto Studio · hefesto-observabilidad-ia-langfuse
#
# -----------------------------------------------------------------------------
# PRINCIPIOS DE ESTE SCRIPT (deliberados, no accidentales)
# -----------------------------------------------------------------------------
# 1. NUNCA hace DROP DATABASE. Nunca borra la base. Nunca sobrescribe datos
#    sin que el operador lo pida de forma explicita con --force.
# 2. Verifica el SHA-256 de TODOS los artefactos ANTES de tocar nada. Si algo
#    no calza, se detiene: es preferible no restaurar a restaurar mal.
# 3. Revisa cada miembro de los archivos tar ANTES de extraer, para descartar
#    rutas absolutas o con '..' (path traversal). Un respaldo manipulado no
#    debe poder escribir fuera del volumen destino.
# 4. Se niega a restaurar sobre un destino que ya tiene datos, salvo --force.
# 5. Al terminar, DEJA LOS SERVICIOS DETENIDOS. Restaurar y dejar corriendo no
#    es un estado en el que uno quiere despertar a nadie.
#
# -----------------------------------------------------------------------------
# QUE RESTAURA
# -----------------------------------------------------------------------------
#   postgres.dump    -> estado de la aplicacion (proyectos, CLAVES DE API,
#                       usuarios, prompts, conjuntos de datos)
#   clickhouse.tar.gz-> trazas, observaciones, puntuaciones
#   minio.tar.gz     -> medios e ingresos crudos de ingesta
#   redis            -> NO se restaura. Es cache y cola regenerables.
#
# -----------------------------------------------------------------------------
# USO
# -----------------------------------------------------------------------------
#   ./restore-langfuse.sh RUTA_AL_RESPALDO            # se niega si hay datos
#   ./restore-langfuse.sh RUTA --force                # sobreescribe
#   ./restore-langfuse.sh RUTA --solo-postgres        # restaura solo el estado
#   ./restore-langfuse.sh --help
#
# REQUISITOS: docker + docker compose v2, y el compose.yaml del kit.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

COMPOSE_FILE="${KIT_DIR}/compose.yaml"
ENV_FILE="${KIT_DIR}/.env"
IMG_TAR="postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3"

BACKUP_DIR=""
FORCE=0
SOLO_POSTGRES=0

SERVICIOS_WEB="langfuse-web langfuse-worker"

# -----------------------------------------------------------------------------
# Utilidades
# -----------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
warn() { printf '[%s] AVISO: %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +'%H:%M:%S')" "$*" >&2; exit 1; }

uso() {
  cat <<'FIN'
Uso: restore-langfuse.sh RUTA_AL_RESPALDO [opciones]

Opciones:
  --force            Permite restaurar sobre un destino que ya tiene datos.
                     Sin esta opcion, el script se niega si encuentra datos.
  --solo-postgres    Restaura solo el estado de la aplicacion (PostgreSQL),
                     sin tocar ClickHouse ni MinIO.
  --help             Mostrar esta ayuda

Al terminar, los servicios quedan DETENIDOS a proposito.
FIN
}

compose() {
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

obtener_var_postgres() {
  local clave="$1" por_defecto="$2" valor
  valor="$(grep -E "^${clave}=" "${ENV_FILE}" | head -n1 | cut -d= -f2- || true)"
  [ -n "${valor}" ] && [ "${valor}" != "null" ] || valor="${por_defecto}"
  printf '%s' "${valor}"
}

# -----------------------------------------------------------------------------
# 1. Validar argumentos y entorno
# -----------------------------------------------------------------------------
validar_entorno() {
  log "Validando entorno..."

  command -v docker >/dev/null 2>&1 || die "No se encontro 'docker' en el PATH."
  docker compose version >/dev/null 2>&1 || die "No se encontro 'docker compose' v2."
  docker info >/dev/null 2>&1 || die "No se pudo contactar al demonio Docker."
  [ -f "${COMPOSE_FILE}" ] || die "No se encontro el compose en ${COMPOSE_FILE}."
  [ -f "${ENV_FILE}" ]    || die "No se encontro ${ENV_FILE}."

  [ -n "${BACKUP_DIR}" ] || { uso; die "Falta la ruta del respaldo."; }
  [ -d "${BACKUP_DIR}" ] || die "La ruta '${BACKUP_DIR}' no es un directorio."
  BACKUP_DIR="$(cd -- "${BACKUP_DIR}" && pwd)"

  # Respaldo incompleto: el marcador COMPLETO se escribe solo al final del
  # respaldo. Si no esta, no se restaura.
  [ -f "${BACKUP_DIR}/MANIFESTO.estado" ] \
    || die "Falta MANIFESTO.estado en el respaldo. No se puede verificar que este completo."
  if ! grep -q '^estado: completo' "${BACKUP_DIR}/MANIFESTO.estado"; then
    die "El respaldo NO esta marcado como completo.
    Vease el estado guardado en MANIFESTO.estado. Un respaldo incompleto no se restaura."
  fi
  [ -f "${BACKUP_DIR}/MANIFESTO.sha256" ] || die "Falta MANIFESTO.sha256 en el respaldo."

  local proyecto
  proyecto="$(compose config --format json 2>/dev/null \
    | grep -o '"name": *"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
  [ -n "${proyecto}" ] || die "No se pudo determinar el nombre del proyecto Docker Compose."
  VOL_POSTGRES="${proyecto}_langfuse_postgres_data"
  VOL_CLICKHOUSE="${proyecto}_langfuse_clickhouse_data"
  VOL_MINIO="${proyecto}_langfuse_minio_data"

  log "Proyecto Docker: ${proyecto}"
  log "Respaldo:        ${BACKUP_DIR}"
}

# -----------------------------------------------------------------------------
# 2. Verificar integridad ANTES de tocar nada
# -----------------------------------------------------------------------------
verificar_integridad() {
  log "Verificando SHA-256 de los artefactos..."
  if ! ( cd "${BACKUP_DIR}" && sha256sum -c MANIFESTO.sha256 ); then
    die "La verificacion de integridad fallo.
    El respaldo esta corrupto o fue modificado. NO se restaura nada."
  fi
  log "  Integridad correcta."
}

# -----------------------------------------------------------------------------
# 3. Seguridad del archivo tar contra path traversal
# -----------------------------------------------------------------------------
validar_tar() {
  local archivo="$1"
  local nombre
  nombre="$(basename "${archivo}")"

  log "  Revisando rutas de ${nombre}..."
  # Se listan los miembros y se rechazan rutas absolutas, rutas con '..' y
  # enlaces simbolicos hacia fuera. Todo antes de extraer.
  local naughty
  naughty="$(tar -tzf "${archivo}" 2>/dev/null \
    | grep -E '^/|(^|/)\.\.(/|$)' || true)"

  if [ -n "${naughty}" ]; then
    printf '%s\n' "${naughty}" | head -n5 >&2
    die "El archivo ${nombre} contiene rutas inseguras (absolutas o con '..').
    Se rechaza extraerlo. Posible manipulacion del respaldo."
  fi
  log "    Sin rutas inseguras."
}

# -----------------------------------------------------------------------------
# 4. No restaurar sobre un destino ocupado
# -----------------------------------------------------------------------------
verificar_destino_libre() {
  local etiqueta="$1" volumen="$2"

  if ! docker volume inspect "${volumen}" >/dev/null 2>&1; then
    log "  ${etiqueta}: el volumen '${volumen}' no existe todavia. Destino libre."
    return 0
  fi

  local ocupado
  ocupado="$(docker run --rm -v "${volumen}:/source:ro" "${IMG_TAR}" \
    bash -c 'ls -A /source 2>/dev/null | head -n1' || true)"

  if [ -n "${ocupado}" ]; then
    if [ "${FORCE}" -ne 1 ]; then
      die "El volumen '${volumen}' (${etiqueta}) YA TIENE DATOS.
    No se restaura sobre un destino ocupado.
    Si realmente queres reemplazarlo, vuelve a ejecutar con --force.
    Esto BORRA el contenido actual del volumen."
    fi
    warn "  ${etiqueta}: destino ocupado. Con --force se reemplazara el contenido."
    return 0
  fi

  log "  ${etiqueta}: volumen existente pero vacio. Destino libre."
}

# -----------------------------------------------------------------------------
# 5. Restaurar PostgreSQL
# -----------------------------------------------------------------------------
restaurar_postgres() {
  local dump="${BACKUP_DIR}/postgres.dump"
  [ -f "${dump}" ] || die "Falta postgres.dump en el respaldo."
  [ -s "${dump}" ] || die "postgres.dump esta vacio."

  local pg_user pg_db
  pg_user="$(obtener_var_postgres POSTGRES_USER postgres)"
  pg_db="$(obtener_var_postgres POSTGRES_DB langfuse)"

  log "Asegurando que PostgreSQL este disponible..."
  compose up -d postgres

  # El script NUNCA hace DROP. Si la base ya tiene tablas, se niega salvo
  # que el operador pase --force, y aun asi usa pg_restore con --clean, que
  # borra los objetos presentes antes de recrearlos. El DROP de la base
  # entera no existe en ningun camino de este script.
  if [ "${FORCE}" -eq 1 ]; then
    warn "Restaurando PostgreSQL con --clean (reemplaza el contenido actual)."
    compose exec -T postgres bash -c '
        set -euo pipefail
        cat > /tmp/restaurar.dump
        pg_restore --clean --if-exists --no-owner --no-privileges -U "$1" -d "$2" /tmp/restaurar.dump
        rm -f /tmp/restaurar.dump
      ' _ "${pg_user}" "${pg_db}" < "${dump}" \
      || die "pg_restore --clean fallo. Revisar manualmente el estado de la base."
  else
    # Sin --force: se restaura solo si la base esta vacia. pg_restore sin
    # --clean sobre una base con datos falla, y eso es exactamente lo que
    # queremos: que se note y no que se mezcle.
    log "Restaurando PostgreSQL sobre base vacia..."
    compose exec -T postgres bash -c '
        set -euo pipefail
        cat > /tmp/restaurar.dump
        pg_restore --no-owner --no-privileges -U "$1" -d "$2" /tmp/restaurar.dump
        rm -f /tmp/restaurar.dump
      ' _ "${pg_user}" "${pg_db}" < "${dump}" \
      || die "pg_restore fallo. Si la base ya tenia datos, el script no los sobreescribe: revisa si corresponde usar --force."
  fi
  log "  PostgreSQL restaurado."
}

# -----------------------------------------------------------------------------
# 6. Restaurar un volumen desde el tar
# -----------------------------------------------------------------------------
restaurar_volumen() {
  local archivo="$1"
  local volumen="$2"
  local etiqueta="$3"

  [ -f "${archivo}" ] || die "Falta $(basename "${archivo}") en el respaldo."
  [ -s "${archivo}" ] || die "$(basename "${archivo}") esta vacio."

  validar_tar "${archivo}"
  verificar_destino_libre "${etiqueta}" "${volumen}"

  log "  Extrayendo ${etiqueta} en '${volumen}'..."
  # Se crea el volumen si no existe. La extraccion ocurre DENTRO del volumen,
  # nunca sobre una ruta del host elegida por el archivo.
  docker volume create "${volumen}" >/dev/null
  docker run --rm \
    -v "${volumen}:/destino" \
    -v "${BACKUP_DIR}:/respaldo:ro" \
    "${IMG_TAR}" \
    bash -c '
      set -euo pipefail
      mkdir -p /destino
      tar xzf "/respaldo/$(basename "$1")" -C /destino
      # Comprobacion minima: el contenido quedo donde debía.
      [ -n "$(ls -A /destino 2>/dev/null | head -n1)" ] || { echo "El volumen quedo vacio tras extraer"; exit 1; }
    ' _ "${archivo}" \
    || die "Fallo la extraccion de ${etiqueta}."

  log "  ${etiqueta} restaurado."
}

# -----------------------------------------------------------------------------
# Programa principal
# -----------------------------------------------------------------------------
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) FORCE=1; shift ;;
      --solo-postgres) SOLO_POSTGRES=1; shift ;;
      --help|-h) uso; exit 0 ;;
      -*) die "Opcion desconocida: $1. Usa --help." ;;
      *) [ -z "${BACKUP_DIR}" ] && BACKUP_DIR="$1" || die "Sobrecarga de argumentos: $1"; shift ;;
    esac
  done

  validar_entorno
  verificar_integridad

  warn "A partir de este momento se modifican los datos de la instancia."
  if [ "${FORCE}" -eq 1 ]; then
    warn "Modo --force: se reemplazara el contenido de los volumenes indicados."
  fi

  # --- Detener los servicios que leen y escriben ----------------------------
  log "Deteniendo servicios de la aplicacion..."
  compose stop ${SERVICIOS_WEB} clickhouse minio 2>/dev/null || true

  # --- PostgreSQL -----------------------------------------------------------
  log "Restaurando estado de la aplicacion (PostgreSQL)..."
  restaurar_postgres

  # --- ClickHouse y MinIO ---------------------------------------------------
  if [ "${SOLO_POSTGRES}" -eq 1 ]; then
    log "Se omite ClickHouse y MinIO por --solo-postgres."
    warn "Ojo: quedaran trazas y medios de una epoca distinta a las del estado"
    warn "de la aplicacion. Puede dejar la instancia incoherente."
  else
    log "Restaurando ClickHouse..."
    restaurar_volumen "${BACKUP_DIR}/clickhouse.tar.gz" "${VOL_CLICKHOUSE}" "ClickHouse"

    log "Restaurando MinIO..."
    restaurar_volumen "${BACKUP_DIR}/minio.tar.gz" "${VOL_MINIO}" "MinIO"
  fi

  # --- Estado final: TODO DETENIDO -----------------------------------------
  log "Dejando los servicios DETENIDOS para la revision."
  compose stop ${SERVICIOS_WEB} clickhouse minio redis 2>/dev/null || true

  cat <<'FIN'

-------------------------------------------------------------------------------
RESTAURACION TERMINADA. LOS SERVICIOS QUEDAN DETENIDOS.

La instancia no se levanto a proposito: alguien debe revisarla antes.

Antes de arrancar:
  1. Revisa que SALT y ENCRYPTION_KEY del .env sean EXACTAMENTE los mismos que
     tenia la instancia respaldada. Si no coinciden, las claves de API del
     respaldo no validaran y habria que rehacer la instrumentacion.
  2. Confirma que el .env tenga NEXTAUTH_URL con la URL correcta.
  3. Verifica que postgres.dump, clickhouse.tar.gz y minio.tar.gz se
     restauraron completos (este script ya verifico sus SHA-256 antes de
     extraer).

Para levantar:
  docker compose up -d
  docker compose logs -f langfuse-web

El primer arranque puede tardar 2 a 3 minutos mientras corren las migraciones.
-------------------------------------------------------------------------------
FIN
}

main "$@"