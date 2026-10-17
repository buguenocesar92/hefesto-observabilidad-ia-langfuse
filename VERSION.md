# VERSION.md — Hefesto Studio · Kit Langfuse

Estado del kit: **kit preparado**. Ninguna imagen fue descargada ni ejecutada en
la preparacion de este kit. Los digests que aparecen aqui se resolvieron
consultando los registros de imagenes por HTTP; no se construyo ni se levanto
ningun contenedor.

Ultima actualizacion de esta tabla: 2026-10-17.

---

## 1. Aplicacion

| Dato | Valor | Como se verifico |
| --- | --- | --- |
| Producto | Langfuse | [langfuse.com](https://langfuse.com) |
| Version estable mas reciente | **v4.63.0** | API de releases de GitHub, `/releases/latest`, consultada 2026-10-17 |
| Fecha de publicacion de v4.63.0 | 2026-10-16 | Campo `published_at` de la misma API |
| Imagen web (etiqueta upstream) | `docker.langfuse.com/langfuse/langfuse:4` | `docker-compose.yml` del tag v4.63.0 |
| Imagen worker (etiqueta upstream) | `docker.langfuse.com/langfuse/langfuse-worker:4` | `docker-compose.yml` del tag v4.63.0 |

**Aviso importante sobre las etiquetas.** Upstream publica `langfuse:4` y
`langfuse-worker:4`, que son etiquetas **flotantes** dentro de la rama 4.x: no
identifican un build concreto. Un `docker compose pull` en otro dia puede
traer una version distinta. Por eso este kit los fija **por digest**, no por
etiqueta. La equivalencia entre el digest fijado y la version v4.63.0 se
comprueba en `docs/07-PRUEBAS-DE-ACEPTACION.md`, porque resolver un digest no
revela por si mismo la etiqueta de version que contiene.

---

## 2. Digests fijados en `compose.yaml`

Resueltos el 2026-10-17 consultando la API de manifiesto de cada registro.
Formato: `sha256:...`.

| Servicio | Referencia en `compose.yaml` | Digest resuelto | Registro |
| --- | --- | --- | --- |
| `langfuse-web` | `langfuse/langfuse` | `sha256:67f48d12a190e4ad585249c75ae1ce172b449de3dbbe7486b8179cd28e21408e` | Docker Hub |
| `langfuse-worker` | `langfuse/langfuse-worker` | `sha256:ca32a8fb2a214c7b5f42dd9c540c8072e41db659cb621f317911ce695ad6bca2` | Docker Hub |
| `clickhouse` | `clickhouse/clickhouse-server` | `sha256:8a790dd3468db22b1d4e7b18a176f378ff5ff6053b9c48dd4ea1fa71a24c5ba6` | Docker Hub |
| `redis` | `redis` | `sha256:4fa24486b8bcca8eec45ee0eb166edc674795e53a2b53d1a9ef263eecebaac85` | Docker Hub |
| `postgres` | `postgres` | `sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3` | Docker Hub |

Los digests corresponden a los indices multi-arquitectura (manifest list), por
lo que el mismo `compose.yaml` funciona en amd64 y arm64.

### Por que `postgres` y `redis` se fijan sin etiqueta

Upstream escribe `docker.io/postgres:${POSTGRES_VERSION:-17}` y
`docker.io/redis:7`. Se resolvio el digest de `postgres:17` y de `redis:7` para
anclar exactamente las mismas versiones, sin depender de la interpolacion de
variables en el `compose.yaml`.

---

## 3. Componente que NO se pudo fijar: MinIO

| Servicio | Referencia | Situacion |
| --- | --- | --- |
| `minio` | `cgr.dev/chainguard/minio:latest` | **Digest NO verificado** |

Motivo, verificado el 2026-10-17: el registro `cgr.dev` responde **HTTP 401**
a toda peticion de manifiesto y exige un token emitido por su proveedor de
identidad OIDC. No es posible obtener el digest de forma anonima.

Consecuencias y mitigacion:

- La referencia **queda flotante**. Un `docker compose pull` puede trae una
  version distinta de MinIO sin avisar.
- Se conservo la imagen que usa upstream, y no una alternativa de Docker Hub,
  a proposito: cambiar el almacen de objetos por cuenta propia puede alterar el
  comportamiento de Langfuse sin que se note.
- **Como fijarla en el servidor**, una sola vez, con Docker funcionando:

  ```bash
  docker compose pull minio
  MINIO_DIGEST=$(docker image inspect cgr.dev/chainguard/minio:latest \
    --format '{{index .RepoDigests 0}}')
  echo "$MINIO_DIGEST"
  # Reemplazar en compose.yaml la referencia por su digest.
  ```

Este paso queda como pendiente en `docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## 4. Topologia verificada del tag v4.63.0

Leida del `docker-compose.yml` oficial del tag, no de guias de terceros.
**La topologia cambio varias veces entre versiones mayores de Langfuse**: lo que
dicen textos viejos no es confiable.

| Servicio | Imagen | Rol | Puerto publicado por upstream |
| --- | --- | --- | --- |
| `langfuse-web` | `langfuse:4` | Interfaz web y API publica de ingesta | `3000:3000` |
| `langfuse-worker` | `langfuse-worker:4` | Procesamiento en segundo plano | `127.0.0.1:3030:3030` |
| `clickhouse` | `clickhouse-server:25.12` | **Almacen de eventos** | `127.0.0.1:8123`, `127.0.0.1:9000` |
| `postgres` | `postgres:17` | **Estado de la aplicacion** | `127.0.0.1:5432:5432` |
| `redis` | `redis:7` | Cola de trabajos y cache | `127.0.0.1:6379:6379` |
| `minio` | `chainguard/minio` | Almacen de objetos S3 | `9090:9000` y `127.0.0.1:9091:9001` |

### El punto critico: hay DOS almacenes, no uno

Es la CONCLUSION mas importante de este kit y define todo el plan de respaldo.

- **PostgreSQL** guarda el estado: usuarios, organizaciones, proyectos,
  membresias, **claves de API**, prompts, conjuntos de datos, ajustes.
- **ClickHouse** guarda los eventos: trazas, observaciones, puntuaciones
  (scores), uso y costos.

La documentacion de upstream es explicita: Langfuse no puede autoalojarse sin
ClickHouse. No es un componente opcional ni un extra para escala.

Consecuencia practica: **un respaldo que solo copie PostgreSQL pierde todas las
trazas.** Y un respaldo que solo copie ClickHouse pierde los proyectos y las
claves de API, con lo que la instrumentacion existente deja de funcionar y hay
que rehacerla. Ver `docs/05-RESPALDOS-Y-RESTAURACION.md`.

---

## 5. Requisitos de version de los dependents

Verificado contra la documentacion de Langfuse.

| Elemento | Version minima | Fuente |
| --- | --- | --- |
| Langfuse v4 (este kit) | v4.63.0 | Release de GitHub |
| Python SDK v5 | servidor >= v4.59.0 | docs de SDK |
| JS/TS SDK v6 | servidor >= v4.59.0 | docs de SDK |
| ClickHouse | **25.12 o superior** | docs de infraestructura ClickHouse |
| PostgreSQL | minimo **15**, se recomienda **16** | docs de infraestructura Postgres |

Upstream fijó PostgreSQL 17 en su compose y ClickHouse 25.12. Este kit mantiene
ambas versiones, fijadas por digest.

Detalle sobre ClickHouse: la documentacion menciona que **26.4** es la version
recomendada y que debe correr en **UTC**. Este kit se queda en 25.12, que es lo
que usa el compose oficial del tag, y por eso el compose fija `TZ: UTC`.

---

## 6. Lo que quedo sin verificar en este entorno

Este kit se preparo **sin Docker y sin servidor**. Lo siguiente esta escrito a
partir de fuentes oficiales, pero **no se ejecuto**:

- Que las imagenes realmente levanten y pasen los healthchecks.
- Que el digest fijado corresponda al build etiquetado v4.63.0.
- Cuanto tarda el primer arranque. Upstream advierte que el servicio web puede
  tardar **2 a 3 minutos** en registrar "Ready" mientras corren las migraciones.
- El comportamiento real de la previsualizacion de medios (ver README, seccion
  "Medios y MinIO").

El detalle completo esta en `docs/07-PRUEBAS-DE-ACEPTACION.md`, separado entre
lo verificado y lo pendiente. No se presento ninguna simulacion como prueba real.

---

## 7. Como actualizar a una version nueva de Langfuse

1. Consultar la release en
   `https://api.github.com/repos/langfuse/langfuse/releases/latest`.
2. Leer las notas de la release y el archivo `docker-compose.yml` **de ese tag**,
   porque la topologia y las variables cambian entre versiones mayores.
3. Resolver los digests nuevos de `langfuse/langfuse` y `langfuse/langfuse-worker`
   y reemplazarlos en `compose.yaml`.
4. Respaldar **antes** de actualizar. Ver `docs/05-RESPALDOS-Y-RESTAURACION.md`.
5. Actualizar y revisar `docs/06-ACTUALIZACIONES-Y-REVERSION.md` para el orden
   correcto y para las migraciones que no se pueden deshacer.

El procedimiento completo esta en `docs/06-ACTUALIZACIONES-Y-REVERSION.md`.