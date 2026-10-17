# 02 — Instalación en Coolify

> **Alcance de este documento.** Explica cómo desplegar este kit como recurso
> "Docker Compose" en Coolify, **y por qué Hefesto no lo recomienda por
> defecto**. Al final está la alternativa que sí se recomienda.

---

## 1. ¿Sirve este kit para Coolify?

**Sí, se puede.** El `compose.yaml` es un compose estándar y Coolify lo puede
levantar. Pero hay tres cosas que hacen que **el camino directo de Docker sea
mejor** para la operación de Hefesto:

1. **Coolify administra el dominio y el proxy**, y eso implica que `NEXTAUTH_URL`
   queda determinado por Coolify, no por el operador. Si se cambia el dominio,
   hay que cambiar `NEXTAUTH_URL` al mismo tiempo o la autenticación se rompe.
2. **La política de respaldos queda fuera del control de Hefesto.** En Coolify
   no basta con el script de este kit: hay que revisar además el respaldo que
   Coolify aplica a los volúmenes.
3. **Este kit publica en `127.0.0.1:3000`.** Coolify espera exponer el servicio en
   un puerto del contenedor y enrutar Traefik hacia él. Hay que declarar el
   puerto `3000` y configurar el dominio, no la IP.

Si el cliente ya usa Coolify para todo lo demás, tiene sentido mantenerlo. Si no,
instala con Docker directo.

---

## 2. Despliegue paso a paso

### Paso 1 — Crear el recurso

1. En Coolify, **New Resource** → **Docker Compose**.
2. Nombre sugerido: `langfuse`.
3. Pegar el contenido de `compose.yaml`.

### Paso 2 — Generar las variables

En la sección de **Environment Variables**, define las variables de
`.env.example`. Coolify guarda estos valores en su propio almacén, lo que es una
ventaja real frente a un `.env` en disco.

Como mínimo:

| Variable | Valor |
| --- | --- |
| `NEXTAUTH_URL` | `https://observabilidad.ejemplo.cl` |
| `NEXTAUTH_SECRET` | `openssl rand -base64 32` |
| `SALT` | `openssl rand -hex 32` |
| `ENCRYPTION_KEY` | `openssl rand -hex 32` |
| `POSTGRES_PASSWORD` | `openssl rand -base64 24` |
| `CLICKHOUSE_PASSWORD` | `openssl rand -base64 24` |
| `REDIS_AUTH` | `openssl rand -base64 24` |
| `MINIO_ROOT_PASSWORD` | `openssl rand -base64 24` |
| `LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID` | mismo valor que `MINIO_ROOT_USER` |
| `LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY` | mismo valor que `MINIO_ROOT_PASSWORD` |
| `LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID` | mismo valor que `MINIO_ROOT_USER` |
| `LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY` | mismo valor que `MINIO_ROOT_PASSWORD` |
| `AUTH_DISABLE_SIGNUP` | `true` |
| `LANGFUSE_TRUSTED_PROXY_COUNT` | `1` |

> La URL de los medios debe ser alcanzable desde el navegador del usuario.
> `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` queda como `http://localhost:9090` por
> defecto, que **no sirve** para un usuario remoto. Ver el aviso de la sección 4.

### Paso 3 — Puertos

En la configuración del recurso, declara el puerto **3000**, asociado al
servicio `langfuse-web`.

Los puertos de PostgreSQL, Redis, ClickHouse y MinIO **no se declaran**: en este
compose no están publicados. Es intencional.

> Si declaras `3000` en Coolify, conviene quitar el `127.0.0.1:` del `compose.yaml`
> para este escenario, o dejar que el proxy de Coolify enrute al puerto publicado
> en la red de Coolify. **Esto es un cambio al compose y no se probó**: anótalo
> en `07-PRUEBAS-DE-ACEPTACION.md` antes de hacerlo en un servidor real.

### Paso 4 — Dominio y proxy

1. Asigna el dominio, por ejemplo `observabilidad.ejemplo.cl`.
2. Coolify emite el certificado con Let's Encrypt.
3. Verifica que `NEXTAUTH_URL` coincide **exactamente** con ese dominio.

### Paso 5 — Desplegar y observar

```bash
# Desde el servidor, con la CLI de Coolify o por SSH
docker compose logs -f langfuse-web
```

Espera a que aparezca "Ready". Upstream advierte que el primer arranque puede
tardar **2 a 3 minutos**.

---

## 3. Problemas específicos de Coolify

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| El login falla o hace loop | `NEXTAUTH_URL` no coincide con el dominio | Igualar ambas cadenas, carácter por carácter |
| La interfaz carga pero no traza | ClickHouse no está sano | `docker compose ps` y revisar salud de ClickHouse |
| Cambiar el dominio rompe el acceso | `NEXTAUTH_URL` quedó como el anterior | Actualizar la variable y redesplegar |
| El proxy da error 502 | `127.0.0.1` no es alcanzable desde Traefik | Publicar el puerto 3000 sin la restricción de loopback |

`LANGFUSE_TRUSTED_PROXY_COUNT=1` es necesario porque Coolify pone Traefik delante.
Sin él, Langfuse puede leer mal la IP real del cliente y el protocolo.

---

## 4. La alternativa que Hefesto recomienda

Instalar con `docker compose` directamente en el servidor, como en
`01-INSTALACION-DOCKER.md`.

Ventajas para la operación:

- `NEXTAUTH_URL`, el dominio y el proxy quedan bajo control directo.
- Los scripts de respaldo de este kit funcionan sin adaptaciones.
- No hay una capa de abstracción que pueda cambiar el comportamiento entre
  versiones de Coolify.

**Recomendación de Hefesto:** Docker directo, salvo que el cliente ya opere
todo con Coolify por política propia.

---

## 5. Estado de esta vía

No se probó un despliegue real en Coolify. No hay servidor en el entorno donde
se preparó este kit. Lo anterior se escribió leyendo el `compose.yaml` y la
documentación oficial de Langfuse, no ejecutando Coolify.

Está en la lista de pendientes de `07-PRUEBAS-DE-ACEPTACION.md`.