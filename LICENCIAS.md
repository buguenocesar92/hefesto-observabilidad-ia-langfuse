# LICENCIAS.md — Hefesto Studio · Kit Langfuse

Resumen de licencias de cada componente que este kit instala. **Este kit no
distribuye el código de Langfuse**: solo descarga imagenes Docker ya
construidas. Las licencias que importan son las de esas imagenes y las de sus
dependencias.

La tabla resume. Las condiciones exactas, en su texto original, estan en
`docs/10-LICENCIAS-Y-FUENTES.md` con el enlace a la fuente oficial de cada una.

---

## 1. Langfuse — modelo de licencia "open core"

Verificado leyendo los archivos `LICENSE` y `ee/LICENSE` del tag **v4.63.0** en
<https://github.com/langfuse/langfuse>.

Langfuse **ya no es un proyecto de una sola licencia**. Tiene dos capas:

| Capa | Ubicacion en el repositorio | Licencia | Uso |
| --- | --- | --- | --- |
| **Nucleo (core)** | todo lo que esta **fuera** de `ee/`, `web/src/ee/` y `worker/src/ee/` | **MIT Expat** | Libre, sin restriccion, incluso comercial |
| **Empresa (enterprise)** | directorios `ee/`, `web/src/ee/`, `worker/src/ee/` | **Enterprise License** de Langfuse | Solo con acuerdo y licencia Enterprise vigente |

Titular de los derechos de autor según ambos archivos: **ClickHouse, Inc.**
(2023-2026). Esto refleja la incorporacion de Langfuse a ClickHouse; no cambia
las licencias.

Texto del encabezado de `ee/LICENSE`, que es la aclaracion mas clara del
propósito:

> Langfuse is an open core project. Langfuse's core is permissively licensed
> (MIT license). Certain parts of the periphery of Langfuse are commercially
> licensed and governed by this Enterprise License. [...] this license does not
> apply to the core of Langfuse as it is defined in its license in the directory
> "/LICENSE" (as opposed to this file "ee/LICENSE") which can be used and run
> without infringing the below license and its licensed materials.

**Que significa para Hefesto, en la práctica:** se puede instalar, modificar y
usar comercialmente el nucleo sin pagar nada a Langfuse. No hay copyleft, no hay
obligacion de publicar el código propio que se conecte por API, y no hay que
atribuir nada en la interfaz del producto. Las funciones de empresa se pueden
usar **si el cliente ya tiene una licencia Enterprise**; sin ella, esas
funciones no estan disponibles.

Funciones identificadas como de pago en la documentacion oficial:

- Retencion de datos (data retention) — la documentacion la marca como
  **Enterprise Edition** en instancias autoalojadas.
- SSO empresarial y aplicación forzada de SSO.
- Aprovisionamiento SCIM.
- Control de acceso detallado (RBAC granular).
- Gestión de políticas de retencion a nivel de organización.
- Registro de auditoria, API SCIM, limites de tasa a medida, SLA de
  disponibilidad, reportes SOC 2 / ISO 27001.

El detalle esta en `docs/08-SERVICIOS-COMERCIALES.md`, con lo que Hefesto
puede y no puede prometer.

---

## 2. Imagenes de terceros instaladas por `compose.yaml`

| Componente | Imagen | Licencia | Enlace |
| --- | --- | --- | --- |
| PostgreSQL | `postgres` (17) | PostgreSQL License (tipo BSD, permisiva) | <https://www.postgresql.org/about/licence/> |
| ClickHouse | `clickhouse/clickhouse-server` (25.12) | Apache License 2.0 | <https://github.com/ClickHouse/ClickHouse/blob/master/LICENSE> |
| Redis | `redis` (7) | BSD de 3 clausulas (hasta Redis 7.2) / RSALv2 / SSPLv1 (desde Redis 7.4) | <https://redis.io/legal/licenses/> |
| MinIO | `cgr.dev/chainguard/minio` | AGPL v3 (proyecto MinIO) / imagen mantenida por Chainguard | <https://github.com/minio/minio/blob/master/LICENSE> |

### Advertencia real sobre Redis

La licencia de Redis **cambio a las 7.4**: paso de BSD a una triple licencia
RSALv2 / SSPLv1 / AGPLv3. Redis ya no es software libre en sentido estricto
desde esa versión. Este kit fija `redis:7`, cuyo digest corresponde al estado
previo a ese cambio, por lo que el componente tal como queda instalado en este
kit es el de licencia BSD.

Lo que esto significa para Hefesto: **Redis no se distribuye dentro del producto
que vendemos, solo se ejecuta como infraestructura del cliente**. No hay
obligacion de ofrecer el código fuente de Redis. Aun así, conviene verificar el
digest efectivamente desplegado antes de firmarlo ante un cliente, porque un
`pull` posterior podria traer una versión con licencia mas restrictiva.

MinIO, en cambio, es AGPL. Se ejecuta como proceso separado y no se modifica ni
se vincula al producto del cliente, por lo que no se origina la obligacion de
publicar el código del cliente. Esta nota es una lectura prudente del modelo
AGPL, **no un dictamen legal**.

---

## 3. Archivos propios de Hefesto Studio

| Archivo | Licencia | Nota |
| --- | --- | --- |
| `compose.yaml` | MIT (Hefesto Studio) | Configuración de despliegue |
| `.env.example` | MIT (Hefesto Studio) | Plantilla sin secretos |
| `scripts/*.sh` | MIT (Hefesto Studio) | Respaldo y restauración |
| `docs/*.md`, `ejemplos/*.md`, `README.md` | MIT (Hefesto Studio) | Documentacion |

Hefesto Studio es el autor de esta capa de despliegue. **No** es autor de
Langfuse, ni de PostgreSQL, ClickHouse, Redis ni MinIO.

---

## 4. Lo que este kit NO incluye

- El código fuente de Langfuse.
- Código de la aplicación del cliente.
- Ninguna imagen ya descargada: el `compose.yaml` apunta a registros públicos.

## 5. Aviso honesto

Este documento es una lectura técnica de licencias hecha durante la preparacion
del kit, con las fuentes enlazadas. **No es una opinion legal.** Para un cliente
con dudas de cumplimiento, la via correcta es una revision legal.