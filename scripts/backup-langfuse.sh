#!/usr/bin/env bash
# =============================================================================
# backup-langfuse.sh — Respaldo coherente de una instancia Langfuse autoalojada
#
# Kit Hefesto Studio · hefesto-observabilidad-ia-langfuse
# Compatible con: Langfuse v4.63.0 (ver VERSION.md)
#
# -----------------------------------------------------------------------------
# QUE RESPALDA ESTE SCRIPT (y por que son tres, no uno)
# -----------------------------------------------------------------------------
# Langfuse v4 usa DOS almacenes distintos mas un almacen de objetos:
#
#   1. PostgreSQL  -> usuarios, organizaciones, proyectos, membresias,
#                     CLAVES DE API, prompts, conjuntos de datos.
#                     Es lo IRREEMPLAZABLE: sin esto hay que rehacer toda la
#                     instrumentacion de las aplicaciones del cliente.
#   2. ClickHouse  -> trazas, observaciones, puntuaciones, uso y costos.
#                     Es IRREEMPLAZABLE salvo que el cliente los regenere
#                     reejecutando las aplicaciones.
#   3. MinIO (S3)  -> medios subidos e ingresos crudos de ingesta.
#                     Parcialmente regenerable: los medios se pueden volver a
#                     subir, los ingresos crudos solo se recuperan del respaldo.
#   4. Redis       -> NO se respalda. Es cache y cola. Ver el documento de
#                     respaldos para el detalle de la perdida aceptable.
#
# -----------------------------------------------------------------------------
# CÓMO SE OBTIENE UNA COPIA COHERENTE
# -----------------------------------------------------------------------------
# * PostgreSQL: `pg_dump` en formato custom (-Fc). Es consistente por
#   transaccion, asi que se puede ejecutar con la aplicacion EN MARCHA. No
#   hace falta detener nada.
# * ClickHouse y MinIO: se DETIENEN los servicios que escriben (web, worker)
#   y despues los propios motores, y solo entonces se archivan los volumenes.
#   Archivar el volumen de ClickHouse con el servidor corriendo produce una
#   copia inconsistente: esto no es una recomendacion, es lo que hace el
#   script.
#
# -----------------------------------------------------------------------------
# GARANTIAS QUE ENTREGA
# -----------------------------------------------------------------------------
# * Manifiesto MANIFESTO.sha256 con el SHA-256 de cada artefacto.
# * Verificacion de integridad: se comprueba cada SHA-256 al terminar.
# * Marcador COMPLETO escrito **solo** al final, cuando todo salio bien.
#   Si no existe COMPLETO, el respaldo esta incompleto y no se debe usar.
# * El servicio queda como estaba antes de empezar.
#
# -----------------------------------------------------------------------------
# USO
# -----------------------------------------------------------------------------
#   ./backup-langfuse.sh                       # respalda en ./respaldos/
#   ./backup-langfuse.sh --dir /mnt/disco/bk   # elige el destino
#   ./backup-langfuse.sh --help
#
# REQUISITOS: docker + docker compose v2, y el kit desplegado con este
# compose.yaml. El archivo .env debe existir junto al compose.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

COMPOSE_FILE="${KIT_DIR}/compose.yaml"
ENV_FILE="${KIT_DIR}/.env"
DESTINO_BASE="${KIT_DIR}/respaldos"

# Nombres de volumen, tomados del compose.yaml. Si se cambian en el compose,
# hay que cambiarlos aqui.
VOL_POSTGRES="langfuse_langfuse_postgres_data"
VOL_CLICKHOUSE="langfuse_langfuse_clickhouse_data"
VOL_MINIO="langfuse_langfuse_minio_data"

# Imagen auxiliar para archivar volumenes. Se reutiliza la imagen de Postgres
# que YA esta presente en el despliegue, para no obligar a descargar Alpine.
IMG_TAR="postgres@sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3"

# -----------------------------------------------------------------------------
# Utilidades
# -----------------------------------------------------------------------------

log()  { printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
warn() { printf '[%s] AVISO: %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +'%H:%M:%S')" "$*" >&2; exit 1; }

uso() {
  cat <<'FIN'
Uso: backup-langfuse.sh [opciones]

Opciones:
  --dir RUTA   Directorio donde crear el respaldo (por defecto: ./respaldos)
  --help       Mostrar esta ayuda

El respaldo incluye PostgreSQL, ClickHouse y MinIO.
Redis no se respalda por ser cache y cola regenerables.
FIN
}

# -----------------------------------------------------------------------------
# Validaciones previas (nada se toca antes de validar todo)
# -----------------------------------------------------------------------------

validar_entorno() {
  log "Validando entorno..."

  command -v docker >/dev/null 2>&1 \
    || die "No se encontro 'docker' en el PATH."

  docker compose version >/dev/null 2>&1 \
    || die "No se encontro 'docker compose' v2."

  docker info >/dev/null 2>&1 \
    || die "No se pudo contactar al demonio Docker. Revisa permisos o si el servicio esta corriendo."

  [ -f "${COMPOSE_FILE}" ] \
    || die "No se encontro el compose en ${COMPOSE_FILE}."

  [ -f "${ENV_FILE}" ] \
    || die "No se encontro ${ENV_FILE}. Copia .env.example a .env y completalo antes de respaldar."

  # Los nombres de volumen se derivan de docker compose, no se adivinan.
  # Se guarda como variable GLOBAL para usarla al escribir el manifiesto al
  # final del respaldo (en `main`).
  proyecto="$(docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" config --format json 2>/dev/null \
    | grep -o '"name": *"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
  [ -n "${proyecto}" ] || die "No se pudo determinar el nombre del proyecto Docker Compose."

  VOL_POSTGRES="${proyecto}_langfuse_postgres_data"
  VOL_CLICKHOUSE="${proyecto}_langfuse_clickhouse_data"
  VOL_MINIO="${proyecto}_langfuse_minio_data"

  for v in "${VOL_POSTGRES}" "${VOL_CLICKHOUSE}" "${VOL_MINIO}"; do
    docker volume inspect "${v}" >/dev/null 2>&1 \
      || die "No existe el volumen '${v}'. Revisa el nombre del proyecto en compose.yaml (campo 'name:')."
  done

  log "Proyecto Docker: ${proyecto}"
  log "Volumenes a respaldar: ${VOL_POSTGRES}, ${VOL_CLICKHOUSE}, ${VOL_MINIO}"
}

compose() {
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

# -----------------------------------------------------------------------------
# Estado inicial de los servicios, para devolverlos tal como estaban.
# Solo se registran los que YA estaban detenidos: esos son los que hay que
# volver a apagar al final. Los que estaban corriendo deben quedar corriendo.
# -----------------------------------------------------------------------------
SERVICIOS_QUE_ESTABAN_DETENIDOS=()

servicio_esta_corriendo() {
  local svc="$1" cid
  cid="$(compose ps -q "${svc}" 2>/dev/null || true)"
  [ -n "${cid}" ] || return 1
  [ "$(docker inspect -f '{{.State.Running}}' "${cid}" 2>/dev/null || echo false)" = "true" ]
}

registrar_servicios_detenidos() {
  local svc
  for svc in langfuse-web langfuse-worker; do
    if servicio_esta_corriendo "${svc}"; then
      log "  '${svc}' estaba en marcha: quedara en marcha al terminar."
    else
      warn "  '${svc}' ya estaba detenido antes del respaldo. Se dejara detenido."
      SERVICIOS_QUE_ESTABAN_DETENIDOS+=("${svc}")
    fi
  done
}

# -----------------------------------------------------------------------------
# 1. PostgreSQL — lo irremplazable
# -----------------------------------------------------------------------------
respaldar_postgres() {
  local destino="$1"

  log "Respaldando PostgreSQL (volumen ${VOL_POSTGRES})..."

  local pg_user pg_db
  pg_user="$(obtener_var_postgres POSTGRES_USER postgres)"
  pg_db="$(obtener_var_postgres POSTGRES_DB langfuse)"

  # pg_dump -Fc: formato custom, comprimido, restaurable con selectivo.
  # Corre DENTRO del contenedor postgres, que es la forma soportada de hablar
  # con el servidor. -T desactiva la TTY para que la redireccion sea limpia.
  # Se puede ejecutar con la base viva: es consistente por transaccion.
  compose exec -T postgres pg_dump \
      --username "${pg_user}" \
      --dbname "${pg_db}" \
      --format custom \
      --no-password \
      > "${destino}/postgres.dump" 2>"${destino}/.pg_dump.log" \
    || die "pg_dump fallo. Detalle: $(tail -n3 "${destino}/.pg_dump.log" 2>/dev/null || echo 'sin detalle')"

  rm -f "${destino}/.pg_dump.log"
  [ -s "${destino}/postgres.dump" ] || die "El respaldo de PostgreSQL quedo vacio o no se genero."

  # Verificacion real: el archivo debe ser legible para pg_restore. Si esto
  # falla, el respaldo NO sirve y hay que saberlo ahora, no al restaurar.
  compose exec -T postgres bash -c '
      set -euo pipefail
      cat > /tmp/verif.dump
      pg_restore --list /tmp/verif.dump >/dev/null
      rm -f /tmp/verif.dump
    ' < "${destino}/postgres.dump" \
    || die "El dump de PostgreSQL no supero la verificacion pg_restore --list. No es un respaldo utilizable."

  local tamano
  tamano="$(du -h "${destino}/postgres.dump" | cut -f1)"
  log "  PostgreSQL listo: postgres.dump (${tamano}), verificado con pg_restore --list."
}

obtener_var_postgres() {
  # Se lee del .env ya existente; el valor nunca se imprime.
  local clave="$1" por_defecto="$2" valor
  valor="$(grep -E "^${clave}=" "${ENV_FILE}" | head -n1 | cut -d= -f2- || true)"
  [ -n "${valor}" ] && [ -n "${valor}" != "null" ] || valor="${por_defecto}"
  printf '%s' "${valor}"
}

# -----------------------------------------------------------------------------
# 2. Volumenes de ClickHouse y MinIO — con los escritores detenidos
# -----------------------------------------------------------------------------
archivar_volumen() {
  local volumen="$1"
  local salida="$2"
  local etiqueta="$3"

  log "Archivando ${etiqueta} (volumen ${volumen})..."

  docker run --rm \
    -v "${volumen}:/source:ro" \
    -v "$(dirname "${salida}"):/backup" \
    "${IMG_TAR}" \
    tar czf "/backup/$(basename "${salida}")" -C /source . \
    || die "Fallo el archivado de ${etiqueta}."

  [ -s "${salida}" ] || die "El archivo de ${etiqueta} quedo vacio."
  log "  ${etiqueta} listo: $(basename "${salida}") ($(du -h "${salida}" | cut -f1))."
}

# -----------------------------------------------------------------------------
# Programa principal
# -----------------------------------------------------------------------------
main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) DESTINO_BASE="$2"; shift 2 ;;
      --dir=*) DESTINO_BASE="${1#*=}"; shift ;;
      --help|-h) uso; exit 0 ;;
      *) die "Opcion desconocida: $1. Usa --help." ;;
    esac
  done

  validar_entorno
  registrar_servicios_detenidos

  local sello destino
  sello="$(date +'%Y%m%d-%H%M%S')"
  destino="${DESTINO_BASE%/}/langfuse-${sello}"

  # Validacion de ruta: el destino debe ser escribible y no existir todavia,
  # para no mezclar dos respaldos en la misma carpeta.
  mkdir -p "${DESTINO_BASE}" || die "No se pudo crear ${DESTINO_BASE}."
  [ -w "${DESTINO_BASE}" ] || die "El directorio ${DESTINO_BASE} no es escribible."
  [ ! -e "${destino}" ] || die "El destino ${destino} ya existe."

  log "Destino del respaldo: ${destino}"
  mkdir -p "${destino}"

  # --- Se anota el punto de partida. Si el script muere, esta marca lo delata.
  printf 'estado: en_progreso\n' > "${destino}/MANIFESTO.estado"

  # --- Paso 1: PostgreSQL (con la aplicacion en marcha) --------------------
  respaldar_postgres "${destino}"

  # --- Paso 2: detener escritores y motores antes de archivar --------------
  log "Deteniendo servicios para obtener copias consistentes..."
  compose stop langfuse-worker langfuse-web clickhouse minio

  # A partir de aqui, si algo falla, hay que devolver los servicios a la vida.
  trap 'log "ERROR durante el respaldo. Reintentando levantar los servicios..."; compose up -d >/dev/null 2>&1 || warn "Revisar manualmente: docker compose up -d"' ERR

  archivar_volumen "${VOL_CLICKHOUSE}" "${destino}/clickhouse.tar.gz" "ClickHouse (trazas y observaciones)"
  archivar_volumen "${VOL_MINIO}"      "${destino}/minio.tar.gz"      "MinIO (medios e ingresos crudos)"

  # --- Paso 3: devolver los servicios a su estado anterior ------------------
  log "Volviendo a levantar los servicios..."
  compose up -d
  # Si alguno estaba detenido antes del respaldo, se vuelve a dejar detenido.
  if [ "${#SERVICIOS_QUE_ESTABAN_DETENIDOS[@]}" -gt 0 ]; then
    log "Devolviendo a su estado original los servicios que estaban detenidos: ${SERVICIOS_QUE_ESTABAN_DETENIDOS[*]}"
    compose stop "${SERVICIOS_QUE_ESTABAN_DETENIDOS[@]}" || warn "Revisar manualmente esos servicios."
  fi
  trap - ERR

  # --- Paso 4: manifiesto y verificacion, AL FINAL --------------------------
  log "Calculando SHA-256 de los artefactos..."
  ( cd "${destino}" && sha256sum postgres.dump clickhouse.tar.gz minio.tar.gz > MANIFESTO.sha256 )

  log "Verificando los SHA-256..."
  ( cd "${destino}" && sha256sum -c MANIFESTO.sha256 ) | sed 's/^/    /' \
    || die "La verificacion de integridad fallo. El respaldo NO es confiable."

  # --- Paso 5: el respaldo se marca completo solo ahora ---------------------
  {
    printf 'estado: completo\n'
    printf 'completado: %s\n' "$(date +'%Y-%m-%dT%H:%M:%S%z')"
    printf 'kit: hefesto-observabilidad-ia-langfuse\n'
    printf 'langfuse_version: v4.63.0\n'
    printf 'proyecto_compose: %s\n' "${proyecto}"
    printf 'artefactos:\n'
    printf '  postgres.dump   = estado de la aplicacion (IRREEMPLAZABLE: claves de API, proyectos, usuarios)\n'
    printf '  clickhouse.tar.gz = trazas, observaciones, puntuaciones\n'
    printf '  minio.tar.gz    = medios e ingresos crudos de ingesta\n'
    printf 'no_respaldado:\n'
    printf '  redis (langfuse_redis_data) = cache y cola, regenerable\n'
    printf '  clickhouse_logs (langfuse_clickhouse_logs) = logs, descartables\n'
  } > "${destino}/MANIFESTO.estado"

  log ""
  log "Respaldo COMPLETO y verificado: ${destino}"
  log "Archivos:"
  ls -lh "${destino}" | sed 's/^/    /'
  log ""
  warn "Guarda SALT y ENCRYPTION_KEY del .env en un gestor de secretos."
  warn "Sin esos dos valores, las claves de API del respaldo no validadas y"
  warn "habria que rehacer la instrumentacion. No estan en este respaldo."
}

main "$@"