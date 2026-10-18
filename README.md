# Kit de despliegue Langfuse — Observabilidad para aplicaciones de IA

**Hefesto Studio** · Observabilidad para aplicaciones de IA
Versión del kit: Langfuse **v4.63.0** · Estado: **`kit preparado`**

---

## Qué es esto

Un kit para desplegar **Langfuse**, la plataforma open source de observabilidad
para aplicaciones de IA. Langfuse registra **cada llamada que tu aplicación le
hace a un modelo** y responde tres preguntas que hoy no tienen respuesta fácil:

1. **¿Cuánto cuesta?** Desglose por modelo, por usuario, por conversación.
2. **¿Dónde se demora?** Latencia de cada paso.
3. **¿Qué está fallando?** Qué prompts producen respuestas malas.

En otras palabras: sin esto, el cliente no sabe cuánto gasta por conversación,
qué prompts fallan ni dónde está la latencia. Con esto, lo sabe.

---

## Langfuse NO es un producto de IA

Esto hay que entenderlo antes que nada, porque se confunde seguido:

> **Langfuse no ejecuta modelos ni los entrena.** Es la capa de observabilidad.

| | Dify (kit `hefesto-dify-ia-aplicada`) | Langfuse (este kit) |
| --- | --- | --- |
| Qué hace | **Construye** la aplicación: chatbots, RAG, agentes | **Mide** lo que ya pasó |
| Ejecuta modelos | Sí, vía los proveedores | **No** |
| Relación | Orquesta | Observa |

**Dify construye la aplicación, Langfuse la mide.** Se pueden usar juntos o por
separado, y Langfuse funciona con cualquier proveedor de modelos, no solo con
Dify.

**Este kit no es de IA local y no requiere GPU.** Observa modelos que ya se están
usando, en la nube o donde estén. No se promete rendimiento de modelos ni de
hardware.

---

## Estado del kit

> **`kit preparado`.**
>
> Los archivos están escritos. **No hay Docker ni servidor en el entorno donde se
> preparó este kit**, así que **nada se ha ejecutado**: no se descargó ninguna
> imagen, no se levantó ningún contenedor, no se corrió ningún respaldo.
>
> Lo que **sí** se verificó fue la información contra fuentes oficiales
> (versiones, licencias, topología, variables), resolviendo los digests de las
> imágenes por HTTP. Está detallado en `VERSION.md` y en la sección A de
> `docs/07-PRUEBAS-DE-ACEPTACION.md`.
>
> **No se presenta ninguna prueba simulada como real.** La sección B de
> `07-PRUEBAS-DE-ACEPTACION.md` lista, una por una, las comprobaciones que faltan.

---

## Lo que incluye

```
hefesto-observabilidad-ia-langfuse/
├── README.md                    Este documento
├── compose.yaml                 6 servicios, versiones fijadas por digest
├── .env.example                 Sin secretos, obligatorias marcadas
├── .gitignore
├── VERSION.md                   Versiones, digests y su origen
├── LICENCIAS.md                 Licencia de cada componente
├── scripts/
│   ├── backup-langfuse.sh       Respaldo coherente de los 3 almacenes
│   └── restore-langfuse.sh      Restauración con verificaciones y manifiesto
├── ejemplos/
│   ├── 01-INSTRUMENTACION-APLICACION-EXISTENTE.md
│   └── 02-DIFY-LANGFUSE-NATIVO.md
└── docs/                        Los 10 documentos del kit
```

Los scripts pasaron `bash -n` (validación sintáctica). **No se ejecutaron**, porque
no hay Docker aquí.

---

## Requisitos

| Elemento | Detalle |
| --- | --- |
| Sistema | Ubuntu 22.04+ o Debian 12, amd64 o arm64 |
| Docker | Engine con compose v2 |
| CPU / RAM | 2 núcleos / 4 GB como punto de partida |
| Disco | 30 GB **y creciente**: ver la advertencia de retención abajo |
| Puertos | 80 y 443 para el proxy inverso |

> Langfuse no publica una tabla oficial de mínimos para este despliegue. Las cifras
> de arriba son un punto de partida prudente de Hefesto, **no** una cifra de
> upstream. Hay que medirlo en la máquina del cliente.

---

## Inicio rápido

```bash
# 1. Generar los secretos ANTES de crear el .env
openssl rand -hex 32      # SALT
openssl rand -hex 32      # ENCRYPTION_KEY
openssl rand -base64 32   # NEXTAUTH_SECRET
openssl rand -hex 24      # POSTGRES_PASSWORD (hex: va dentro de DATABASE_URL; base64 con /,+,= la rompe)
openssl rand -base64 24   # passwords de ClickHouse, Redis y MinIO

# 2. Configurar
cp .env.example .env
chmod 600 .env
nano .env          # completa NEXTAUTH_URL y todos los secretos

# 3. Levantar
docker compose pull
docker compose up -d
docker compose logs -f langfuse-web     # el primer arranque tarda 2-3 minutos

# 4. Verificar
curl -s http://127.0.0.1:3000/api/public/health

# 5. Primer respaldo, antes de tocar nada más
chmod +x scripts/*.sh
./scripts/backup-langfuse.sh
```

> **Docker directo y Coolify.** Este compose ya no publica puertos. Para
> Docker directo, crea `docker-compose.override.yml` con
> `services.langfuse-web.ports: ["127.0.0.1:3000:3000"]`. Para Coolify,
> Traefik se conecta al contenedor por la red interna; ver la sección
> «Despliegue en Coolify (MVP Hefesto)» más abajo.
>
> **Instalaciones previas (Docker directo).** Este compose ya no fija
> `name:` a nivel raíz, así que sin una variable el proyecto pasa a
> llamarse como el directorio y los volúmenes dejan de ser
> `langfuse_langfuse_*`. Para conservar los volúmenes de una
> instalación existente, define `COMPOSE_PROJECT_NAME=langfuse` en el
> `.env` antes del próximo `docker compose up -d`. En Coolify NO se
> define esta variable.

---

## Despliegue en Coolify (MVP Hefesto)

Coolify levanta este compose como un recurso Docker Compose y enruta el
tráfico con Traefik. El compose está adaptado al contrato de Coolify: sin
puertos publicados, sin `container_name`, sin `name:` fijo a nivel raíz ni
en redes o volúmenes, y nada que dé poder sobre el host.

**Variables nuevas u obligatorias que documenta este kit para Coolify:**

| Variable | Por qué importa en Coolify | Cómo obtenerla |
| --- | --- | --- |
| `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` | La URL que el navegador usa para descargar medios. El default `http://localhost:9090` no es alcanzable para un usuario remoto. **En Coolify**, asignar un dominio al servicio `minio` (puerto 9000) y poner aquí `https://<ese-dominio>`; si no se usan medios desde el navegador, se puede omitir el dominio y dejar el default | `https://<dominio-de-minio>` detrás de Traefik, o vacío (sin medios) |
| `POSTGRES_PASSWORD` | Generar en hexadecimal (`openssl rand -hex 24`). Si se usa base64 con `/`, `+` o `=`, se rompe el armado de `DATABASE_URL` | `openssl rand -hex 24` |
| `AUTH_DISABLE_SIGNUP` | Sin `LANGFUSE_INIT_USER_*`, dejar el registro cerrado deja la instancia sin nadie que pueda crear la cuenta inicial. Para el primer arranque usar `false` o aportar `LANGFUSE_INIT_USER_EMAIL`/`PASSWORD`; cerrar el registro después | `false` en el primer arranque, `true` después |

**Antes de pegar el compose en Coolify** corre el chequeo local:

```bash
bash scripts/coolify-check.sh
```

Debe terminar con `OK: contrato Coolify cumplido`. Cualquier `fail:` indica
un cambio reciente que rompe el contrato y no debe llegar al servidor.

**Después de Coolify**, las claves de API y los respaldos se siguen
manejando como en Docker directo (ver `docs/05-RESPALDOS-Y-RESTAURACION.md`).
Coolify administra el dominio y el proxy; este kit administra secretos,
datos y la política de retención.

Guía completa en `docs/01-INSTALACION-DOCKER.md`.

---

## Arquitectura: dos almacenes, no uno

Este es el punto técnico más importante del kit, porque define todo el plan de
respaldo.

| Servicio | Función | ¿Irreemplazable? |
| --- | --- | --- |
| `langfuse-web` | Interfaz y API de ingesta | — |
| `langfuse-worker` | Procesamiento en segundo plano | — |
| **PostgreSQL 17** | **Estado**: usuarios, proyectos, **claves de API**, prompts | **Sí** |
| **ClickHouse 25.12** | **Eventos**: trazas, observaciones, costos | **Sí** |
| MinIO | Medios subidos e ingresos crudos | Parcialmente |
| Redis 7 | Cola y caché | No, regenerable |

> **ClickHouse es obligatorio.** Langfuse no puede autoalojarse sin él. No es un
> extra para escala.

**Consecuencia:** un respaldo que solo copie PostgreSQL **pierde todas las
trazas**. Uno que solo copie ClickHouse **pierde las claves de API**, y con ellas
la instrumentación deja de funcionar.

---

## Seguridad

| Medida | Estado |
| --- | --- |
| Puertos publicados | **Solo** `127.0.0.1:3000`. Ninguna base de datos expuesta |
| Registro de usuarios | **Cerrado** con `AUTH_DISABLE_SIGNUP=true` |
| Secretos | Todos en `.env`, con permisos `600`, y en `.gitignore` |
| Credenciales administrativas | Nunca en el navegador |
| Datos de un usuario a otro | Dentro de un proyecto, **todos los miembros ven todo** |

> **Ojo con esta confusión.** La variable que cierra el registro es
> **`AUTH_DISABLE_SIGNUP`**. `LANGFUSE_DISABLE_SIGNUP_ONBOARDING` es otra cosa:
> solo omite el paso del formulario de novedades y **no impide crear cuentas**.

### El costo de instrumentar

Instrumentar no es gratis, y es honesto decirlo:

- **Más tráfico de red:** las trazas viajan desde la aplicación al servidor.
- **Más latencia:** los SDK son asíncronos y agregan poca latencia, pero no cero.
- **Los datos salen del servidor del cliente:** los prompts y respuestas quedan
  almacenados en Langfuse. Si hay información sensible, eso es una decisión de
  cumplimiento, no un detalle técnico.
- **El disco crece:** ver la advertencia de retención.

A favor: los SDK capturan sus propios errores y **no pueden romper la
aplicación**.

---

## Límites que hay que conocer antes de vender

| Límite | Detalle |
| --- | --- |
| **Sin retención automática** | En la edición libre **los datos se guardan indefinidamente**. El disco se llena si nadie interviene |
| **Un cliente por instancia** | **No es multi-tenant.** No hay aislamiento entre organizaciones |
| **Acceso sin RBAC fino** | Todos los miembros de un proyecto ven todos los datos |
| **Sin certificaciones** | SOC 2 e ISO 27001 son de los planes de nube |
| **Respaldo con ventana** | Archivar ClickHouse exige detener los servicios unos segundos |
| **Sin alta disponibilidad** | Un solo nodo |
| **Sin conector a Odoo** | Solo exportación CSV/JSON y APIs. Ver `docs/09-EXPORTACION-O-TRASPASO.md` |
| **Sin Supabase** | Solo podría cubrir PostgreSQL. ClickHouse y MinIO seguirían sin resolver. No verificado, no se ofrece |

### Advertencia sobre el disco

> En la edición libre autoalojada **no hay política de retención**. Upstream lo
> documenta: sin configurar una política, los datos se guardan indefinidamente.
> La retención automática es una **función de pago**.
>
> Antes de entregar a un cliente, hay que **acordar una política de conservación**
> y quién vigila el crecimiento del volumen de ClickHouse.

---

## Medios y MinIO — un punto que puede fallar

Langfuse genera **URLs firmadas** para los archivos subidos y **se las pasa al
navegador**. El compose oficial de Langfuse publica el puerto 9090 de MinIO por
eso.

Este kit deja MinIO atado a `127.0.0.1`, así que **es posible que las imágenes
adjuntas a las trazas no se visualicen desde el navegador de un usuario remoto**.

El resto de la funcionalidad (trazas, costos, latencias) **no depende de esto**,
pero el punto queda anotado como pendiente de verificar en
`docs/07-PRUEBAS-DE-ACEPTACION.md`, junto con las dos opciones para resolverlo.

---

## Qué respaldar

| Volumen | Contiene | ¿Se respalda? |
| --- | --- | --- |
| `langfuse_postgres_data` | Proyectos, **claves de API**, usuarios, prompts | **Sí, siempre** |
| `langfuse_clickhouse_data` | Trazas, observaciones, costos | **Sí, siempre** |
| `langfuse_minio_data` | Medios e ingresos crudos | **Sí, siempre** |
| `langfuse_redis_data` | Cola y caché | No, es regenerable |
| `langfuse_clickhouse_logs` | Logs | No |

Detalle en `docs/05-RESPALDOS-Y-RESTAURACION.md`.

### Las claves de API son credenciales

**Esto hay que decirlo siempre al cliente.** Si se pierde el respaldo de
PostgreSQL, **o** se cambian `SALT`, `ENCRYPTION_KEY` o `NEXTAUTH_SECRET`, las
claves de API existentes dejan de validar. En ese caso hay que generar claves
nuevas y **rehacer la instrumentación de todas las aplicaciones**.

No es una molestia administrativa: es trabajo de implementación de nuevo. Por eso
`SALT` y `ENCRYPTION_KEY` se guardan aparte, en un gestor de secretos.

---

## Documentación

| Documento | Para qué |
| --- | --- |
| `01-INSTALACION-DOCKER.md` | Instalación paso a paso en Ubuntu/Debian |
| `02-INSTALACION-COOLIFY.md` | Despliegue en Coolify, y por qué no es el recomendado |
| `03-VARIABLES-Y-COMO-OBTENERLAS.md` | Todas las variables, obligatorias y opcionales |
| `04-PRIMERA-CUENTA-Y-USUARIOS.md` | Primera cuenta, cierre de registro, permisos |
| `05-RESPALDOS-Y-RESTAURACION.md` | Qué es persistente y cómo recuperarlo |
| `06-ACTUALIZACIONES-Y-REVERSION.md` | Actualizar y volver atrás |
| `07-PRUEBAS-DE-ACEPTACION.md` | **Lo verificado y lo pendiente** |
| `08-SERVICIOS-COMERCIALES.md` | Qué se puede vender y qué no se puede prometer |
| `09-EXPORTACION-O-TRASPASO.md` | Exportaciones y límites del traspaso |
| `10-LICENCIAS-Y-FUENTES.md` | Licencias y fuentes oficiales |

---

## Qué es de upstream y qué es de Hefesto

| Parte | Origen |
| --- | --- |
| La aplicación Langfuse y sus imágenes | **Upstream.** MIT (núcleo) |
| `compose.yaml` | **Hefesto.** Adaptación del compose oficial v4.63.0 |
| `.env.example` | **Hefesto** |
| Scripts de respaldo y restauración | **Hefesto.** Código propio |
| Documentación y ejemplos | **Hefesto** |

> **Este kit es un kit de despliegue, no el código de Langfuse.** Solo apunta a
> imágenes Docker construidas por upstream. No incluye código de la aplicación
> del cliente.

---

## Qué falta probar

Todo lo de la sección B de `docs/07-PRUEBAS-DE-ACEPTACION.md`. Lo más relevante:

1. Que las seis imágenes levanten y los healthchecks pasen.
2. Que el digest fijado corresponda al build etiquetado v4.63.0.
3. Que el registro quede efectivamente cerrado.
4. Que lleguen trazas con costo desde una aplicación instrumentada.
5. Que el respaldo se complete y **que la restauración funcione de verdad**.
6. Que los medios se vean desde un navegador remoto.
7. Fijar el digest de MinIO, que no se pudo resolver.

**Lo mínimo antes de entregar en producción** está en la sección C de ese
documento: son seis comprobaciones.

---

## Fuentes principales

- Langfuse: <https://langfuse.com>
- Release v4.63.0: <https://github.com/langfuse/langfuse/releases/tag/v4.63.0>
- Compose del tag: <https://github.com/langfuse/langfuse/blob/v4.63.0/docker-compose.yml>
- Licencias: <https://github.com/langfuse/langfuse/blob/v4.63.0/LICENSE> y [`ee/LICENSE`](https://github.com/langfuse/langfuse/blob/v4.63.0/ee/LICENSE)
- Documentación: <https://langfuse.com/docs> y <https://langfuse.com/self-hosting>
- Precios y límites por plan: <https://langfuse.com/pricing>