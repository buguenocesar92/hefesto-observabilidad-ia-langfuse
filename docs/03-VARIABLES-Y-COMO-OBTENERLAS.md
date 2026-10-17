# 03 — Variables de entorno y cómo obtenerlas

Este documento lista las variables que usa este kit. Las nombres y los valores
por defecto provienen del `docker-compose.yml` oficial del tag **v4.63.0** y de
la página de configuración de Langfuse. **No hay variables inventadas.**

> **Aviso sobre la nomenclatura.** No todas las variables llevan el prefijo
> `LANGFUSE_`. Existen `NEXTAUTH_URL`, `DATABASE_URL`, `SALT`,
> `ENCRYPTION_KEY`, `NEXTAUTH_SECRET`, `CLICKHOUSE_*`, `REDIS_*`, `POSTGRES_*`
> y `MINIO_ROOT_*`. Si buscas solo `LANGFUSE_*`, te van a faltar las más
> importantes.

---

## 1. Cómo generar los secretos

Ejecuta estos comandos **en el servidor**, no acá:

```bash
openssl rand -hex 32      # SALT
openssl rand -hex 32      # ENCRYPTION_KEY   -> debe dar 64 caracteres hex
openssl rand -base64 32   # NEXTAUTH_SECRET
openssl rand -base64 24   # passwords de ClickHouse, Postgres, Redis y MinIO
```

Verificación del largo de `ENCRYPTION_KEY`:

```bash
openssl rand -hex 32 | wc -c      # debe imprimir 65 (64 + salto de linea)
```

---

## 2. Variables obligatorias

Sin estas el despliegue **no arranca**. El `compose.yaml` lo exige con la
sintaxis `:?`, que corta el despliegue si el valor no existe.

### Identidad de la instancia

| Variable | Ejemplo | De dónde sale | Qué pasa si se cambia |
| --- | --- | --- | --- |
| `NEXTAUTH_URL` | `https://observabilidad.ejemplo.cl` | La URL pública que decides | **Rompe el login** y los enlaces. Cambiarla obliga a reiniciar y a corregir la configuración de SSO |
| `NEXTAUTH_SECRET` | `openssl rand -base64 32` | Generada por ti | Invalida todas las sesiones activas. Nadie puede entrar hasta reconfigurar |
| `LANGFUSE_TRUSTED_PROXY_COUNT` | `1` | Número de proxies delante de la app | Con `0` y proxy presente, Langfuse lee mal la IP del cliente y el protocolo |

### Secretos criptográficos — **los más delicados**

| Variable | Ejemplo | De dónde sale | Qué pasa si se cambia |
| --- | --- | --- | --- |
| `SALT` | `openssl rand -hex 32` | Generada por ti | **Las claves de API dejan de validar.** Hay que recrearlas y reinstrumentar las aplicaciones |
| `ENCRYPTION_KEY` | `openssl rand -hex 32` | Generada por ti | Igual que `SALT`. Además, los secretos cifrados almacenados se vuelven ilegibles |

> **Por qué tanto énfasis:** estos dos valores derivan el material con el que se
> validan las claves de API. Un respaldo de PostgreSQL **sin** estos dos valores
> no sirve: las claves que contiene no van a autenticar contra una instancia con
> otros valores. Guárdalos aparte, hoy, en un gestor de secretos.

### Bases de datos y almacenes

| Variable | Ejemplo | De dónde sale | Qué pasa si se cambia |
| --- | --- | --- | --- |
| `POSTGRES_USER` | `langfuse` | Tuyo | Hay que rehacer el `DATABASE_URL` derivado |
| `POSTGRES_PASSWORD` | `openssl rand -base64 24` | Generada por ti | Hay que actualizar la contraseña **dentro** de la base también |
| `POSTGRES_DB` | `langfuse` | Tuyo | El compose arma `DATABASE_URL` con este valor |
| `CLICKHOUSE_USER` | `langfuse` | Tuyo | Se aplica al crear el servidor |
| `CLICKHOUSE_PASSWORD` | `openssl rand -base64 24` | Generada por ti | Hay que cambiarla también dentro de ClickHouse |
| `REDIS_AUTH` | `openssl rand -base64 24` | Generada por ti | Hay que cambiarla también en Redis |
| `MINIO_ROOT_USER` | `langfuse` | Tuyo | Se aplica al crear el almacén de objetos |
| `MINIO_ROOT_PASSWORD` | `openssl rand -base64 24` | Generada por ti | Hay que cambiarla también en MinIO |

> Este kit **no** escribe `DATABASE_URL` a mano: el compose la arma con
> `POSTGRES_USER`, `POSTGRES_PASSWORD` y `POSTGRES_DB`, para que no haya dos
> lugares donde cambiar la misma contraseña.

### Credenciales de la aplicación hacia MinIO

| Variable | Ejemplo | De dónde sale |
| --- | --- | --- |
| `LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID` | `langfuse` | El usuario de MinIO |
| `LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY` | *(la misma contraseña de MinIO)* | Generada por ti |
| `LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID` | `langfuse` | El usuario de MinIO |
| `LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY` | *(la misma contraseña de MinIO)* | Generada por ti |

En este kit, por simplicidad, se usan las mismas credenciales raíz de MinIO para
ambos fines. Un usuario dedicado con permisos limitados es mejor en producción y
queda anotado en `08-SERVICIOS-COMERCIALES.md`.

---

## 3. Variables de seguridad (no negociables en producción)

| Variable | Valor en este kit | Qué hace exactamente |
| --- | --- | --- |
| `AUTH_DISABLE_SIGNUP` | `true` | **Cierra el registro de usuarios nuevos.** Solo entran los que ya existen |
| `LANGFUSE_DISABLE_SIGNUP_ONBOARDING` | `true` | **NO cierra el registro.** Solo omite el paso del formulario de novedades |

> **Confusión habitual, y es importante.** Mucha gente asume que
> `LANGFUSE_DISABLE_SIGNUP_ONBOARDING` es lo que cierra el registro. **No lo es.**
> La variable que lo cierra es **`AUTH_DISABLE_SIGNUP`**.
>
> Verificado en la documentación de autoalojado:
> <https://langfuse.com/self-hosting/security/authentication-and-sso>
>
> Si no se pone `AUTH_DISABLE_SIGNUP=true`, cualquiera que llegue a la URL
> pública puede **crearse su propia cuenta** en la instancia del cliente.

Otras variables de autenticación disponibles (no usadas por este kit):

| Variable | Para qué |
| --- | --- |
| `AUTH_DISABLE_USERNAME_PASSWORD` | Desactiva el acceso con contraseña (solo SSO). Función de pago |
| `AUTH_EMAIL_VERIFICATION_REQUIRED` | Exige verificar el correo antes de crear la contraseña. Requiere correo configurado |
| `AUTH_SESSION_MAX_AGE` | Duración máxima de sesión, en minutos. Por defecto 30 días |
| `AUTH_DOMAINS_WITH_SSO_ENFORCEMENT` | Dominios que solo pueden entrar por SSO |

---

## 4. Variables de medios (MinIO)

| Variable | Por defecto en este kit | Para qué |
| --- | --- | --- |
| `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` | `https://observabilidad.ejemplo.cl` | La URL **que ve el navegador** en las direcciones de los archivos subidos |
| `LANGFUSE_S3_MEDIA_UPLOAD_INTERNAL_ENDPOINT` | `http://minio:9000` | La URL que usa el contenedor para escribir. **No cambiar** |
| `LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT` | `http://minio:9000` | Ingesta de eventos crudos. **No cambiar** |

> `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` es la única de las tres que debe ser
> alcanzable **desde el computador del usuario**, no desde el servidor. Si queda
> apuntando a `http://localhost:9090` y el usuario se conecta de otra máquina,
> las imágenes de las trazas no cargan. Ver `01-INSTALACION-DOCKER.md`, sección 8.

---

## 5. Variables opcionales

### Inicialización sin interfaz (`LANGFUSE_INIT_*`)

Permiten crear organización, proyecto y usuario inicial por variables de entorno.

| Variable | Qué hace |
| --- | --- |
| `LANGFUSE_INIT_ORG_ID`, `LANGFUSE_INIT_ORG_NAME` | Organización inicial |
| `LANGFUSE_INIT_PROJECT_ID`, `LANGFUSE_INIT_PROJECT_NAME` | Proyecto inicial |
| `LANGFUSE_INIT_PROJECT_PUBLIC_KEY`, `LANGFUSE_INIT_PROJECT_SECRET_KEY` | Claves del proyecto inicial |
| `LANGFUSE_INIT_USER_EMAIL`, `LANGFUSE_INIT_USER_NAME`, `LANGFUSE_INIT_USER_PASSWORD` | Usuario inicial |
| `LANGFUSE_INIT_PROJECT_RETENTION` | Días de retención del proyecto inicial. **Función de pago** |

Se aplican **solo en el primer arranque**. Después se pueden vaciar. Hefesto
recomienda crearlas desde la interfaz: poner el *secret key* del proyecto en el
`.env` lo deja en el historial del despliegue.

Verificado en: <https://langfuse.com/self-hosting/administration/headless-initialization>

### Correo

| Variable | Para qué |
| --- | --- |
| `SMTP_CONNECTION_URL` | Servidor SMTP. Sin esto, **"olvidé mi contraseña" no funciona** |
| `EMAIL_FROM_ADDRESS` | Remitente de los correos |

### Correo y ajustes varios

| Variable | Por defecto | Para qué |
| --- | --- | --- |
| `TELEMETRY_ENABLED` | `false` | Telemetría hacia Langfuse. Hefesto la deja apagada |
| `LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES` | `false` | Funciones experimentales |
| `LANGFUSE_OBSERVATION_FIELD_SIZE_LIMIT_BYTES` | `2097152` | Tamaño máximo de un campo de observación |
| `LANGFUSE_OBSERVATION_FIELD_OVERFLOW_ENABLED` | `false` | Qué hacer con los campos que exceden el límite |
| `CLICKHOUSE_CLUSTER_ENABLED` | `false` | Déjalo en `false` para un solo nodo |
| `LANGFUSE_S3_BATCH_EXPORT_ENABLED` | `false` | Exportaciones programadas a almacenamiento de objetos. **Función de pago** |

### Listas de control de red

Se dejan vacías en este kit, lo que significa "política de salida sin cambios".

| Variable | Para qué |
| --- | --- |
| `LANGFUSE_LLM_CONNECTION_WHITELISTED_HOST` | Hosts con los que la interfaz puede llamar a un modelo |
| `LANGFUSE_LLM_CONNECTION_WHITELISTED_IPS` | IPs permitidas para esas llamadas |
| `LANGFUSE_OUTBOUND_BLOCKED_IP_SEGMENTS` | Segmentos de IP bloqueados a la salida |
| `LANGFUSE_WEBHOOK_ALLOWED_HOSTS` | Hosts permitidos para webhooks |
| `LANGFUSE_EXTERNAL_MEDIA_STORAGE_ENDPOINT_ALLOWED_HOSTS` | Hosts permitidos para medios externos |

> Restringirlas es una medida razonable de seguridad, pero **no se probó** en este
> kit. Si las configuras mal, la interfaz deja de poder llamar a los modelos.
> Déjalas vacías al principio y ajústalas con pruebas a la vista.

---

## 6. Variables del cliente instrumentado

Estas **no** van en el `.env` de Langfuse. Van en la aplicación que quieres
observar.

| Variable | Obligatoria | Para qué |
| --- | --- | --- |
| `LANGFUSE_PUBLIC_KEY` | Sí | Identifica el proyecto |
| `LANGFUSE_SECRET_KEY` | Sí | **Credencial.** Autoriza escribir trazas |
| `LANGFUSE_BASE_URL` | Sí en autoalojado | La URL de la instancia |

> **Ojo con el nombre.** La documentación actual usa **`LANGFUSE_BASE_URL`**.
> Muchas guías antiguas usan `LANGFUSE_HOST`, que ya no es la variable correcta
> para los SDK v5 (Python) y v6 (JS/TS).

Detalle en `ejemplos/01-INSTRUMENTACION-APLICACION-EXISTENTE.md`.

---

## 7. Variables de imagen

Las imágenes están fijadas **por digest** en el `compose.yaml`. La excepción es
`cgr.dev/chainguard/minio`, cuyo digest no se pudo resolver porque ese registro
exige autenticación OIDC. Ver `VERSION.md`, sección 3.

---

## 8. Fuentes

- Configuración: <https://langfuse.com/self-hosting/configuration>
- Autenticación y SSO autoalojado: <https://langfuse.com/self-hosting/security/authentication-and-sso>
- Inicialización sin interfaz: <https://langfuse.com/self-hosting/administration/headless-initialization>
- Compose oficial v4.63.0: <https://github.com/langfuse/langfuse/blob/v4.63.0/docker-compose.yml>