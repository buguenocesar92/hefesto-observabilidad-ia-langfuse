# 01 — Instalación con Docker (servidor Ubuntu/Debian)

Estado del kit: **kit preparado**. Este procedimiento está escrito contra la
documentación oficial de Langfuse y contra el `docker-compose.yml` del tag
**v4.63.0**, pero **no se ejecutó** en un servidor real. La lista de
comprobaciones pendientes está en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 1. Requisitos del servidor

| Recurso | Mínimo razonable | Nota |
| --- | --- | --- |
| Sistema | Ubuntu 22.04 o superior / Debian 12 | Linux amd64 o arm64 |
| CPU | 2 núcleos | Sin cifras oficiales de upstream: verificar en la práctica |
| RAM | 4 GB | ClickHouse es el consumidor principal |
| Disco | 30 GB | **Crecen con las trazas.** Ver advertencia abajo |
| Puertos | 80 y 443 (proxy inverso) | El compose **no** pública bases de datos |

> **Honestidad sobre los recursos:** Langfuse no pública una tabla oficial de
> mínimos para este despliegue completo. Los valores de arriba son un punto de
> partida prudente, no una cifra de upstream. Mídelo en la máquina del cliente.

> **Advertencia importante sobre el disco:** en la edición libre autoalojada
> **no hay retención automática**. Los datos se guardan indefinidamente. Ver
> `08-SERVICIOS-COMERCIALES.md`. Hay que vigilar el crecimiento del volumen de
> ClickHouse y definir una política de borrado desde la interfaz.

## 2. Preparación

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl openssl git

# Docker Engine + compose v2, siguiendo la guia oficial de Docker para Ubuntu
# https://docs.docker.com/engine/install/ubuntu/
```

Verifica que Docker quedó operativo y que **tu usuario** puede usarlo sin
`sudo` (para que los scripts del kit funcionen sin Privilegios extra):

```bash
docker run --rm hello-world
docker compose version
```

## 3. Copiar el kit al servidor

```bash
sudo mkdir -p /opt/hefesto/langfuse
sudo chown -R "$USER":"$USER" /opt/hefesto/langfuse
# Copia aqui la carpeta del kit
cd /opt/hefesto/langfuse
```

## 4. Generar los secretos

**Hazlo antes de crear el `.env`.** Estos valores no se pueden recuperar
después.

```bash
openssl rand -hex 32      # SALT
openssl rand -hex 32      # ENCRYPTION_KEY  (64 hex exactos)
openssl rand -base64 32   # NEXTAUTH_SECRET
openssl rand -base64 24   # passwords de ClickHouse, Postgres, Redis y MinIO
```

Guarda `SALT` y `ENCRYPTION_KEY` **fuera del servidor**, en un gestor de
secretos. Sin ellos, las claves de API de los proyectos dejan de validar.

## 5. Crear el `.env`

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Como mínimo debes rellenar:

| Variable | Por qué |
| --- | --- |
| `NEXTAUTH_URL` | La URL pública de la instancia. Debe coincidir exactamente. |
| `NEXTAUTH_SECRET` | Firma las sesiones. |
| `SALT` y `ENCRYPTION_KEY` | Derivación criptográfica. No recuperables. |
| `POSTGRES_PASSWORD` | Acceso a la base de estado. |
| `CLICKHOUSE_PASSWORD` | Acceso al almacén de eventos. |
| `REDIS_AUTH` | Acceso a la cola. |
| `MINIO_ROOT_PASSWORD` | Acceso al almacén de objetos. |
| `LANGFUSE_S3_*_ACCESS_KEY_ID` y `*_SECRET_ACCESS_KEY` | Credenciales de la app hacia MinIO. |
| `AUTH_DISABLE_SIGNUP` | Déjalo en `true` desde el primer arranque. |
| `LANGFUSE_TRUSTED_PROXY_COUNT` | `1` si hay proxy inverso. |

El detalle completo está en `03-VARIABLES-Y-COMO-OBTENERLAS.md`.

## 6. Levantar

```bash
docker compose pull
docker compose up -d
docker compose ps
```

**Paciencia en el primer arranque.** Upstream advierte que el servicio web puede
tardar **2 a 3 minutos** en registrar "Ready" mientras corren las migraciones.
Los logs son la única forma de saber qué pasa:

```bash
docker compose logs -f langfuse-web
```

## 7. Verificar que responde

```bash
# Desde el propio servidor
curl -s http://127.0.0.1:3000/api/public/health
curl -s http://127.0.0.1:3000/api/public/ready
```

Los puertos publicados son **solo** el de la interfaz, atado a `127.0.0.1`.
Comprueba que ningún otro puerto quedó abierto:

```bash
ss -tlnp | grep -E ':(3000|5432|6379|8123|9000|9090|9091|3030)\b'
```

Solo debe aparecer `3000` en `127.0.0.1`. Si PostgreSQL, Redis, ClickHouse o
MinIO aparecen escuchando en `0.0.0.0`, **detén el despliegue**: hay un puerto
expuesto que no debe estarlo.

## 8. Proxy inverso y HTTPS (obligatorio en producción)

Coloca un proxy inverso delante. Caddy es lo más corto:

```bash
sudo apt install -y caddy
```

`/etc/caddy/Caddyfile`:

```
observabilidad.ejemplo.cl {
    encode gzip
    reverse_proxy 127.0.0.1:3000
}
```

```bash
sudo systemctl reload caddy
```

Después de esto, **corrige `NEXTAUTH_URL`** en el `.env` para que apunte a la
URL con HTTPS, y reinicia:

```bash
docker compose up -d
```

### Sobre los medios y MinIO

Este es el punto que más sorprende. Langfuse genera **URLs firmadas** para los
archivos subidos y **se las entrega al navegador**. El compose oficial pública el
puerto 9090 de MinIO justamente por eso.

Este kit deja MinIO atado a `127.0.0.1`, así que **es posible que las imágenes
subidas a trazas no se visualicen desde el navegador de un usuario remoto**.

Esto está documentado como pendiente de verificar en
`07-PRUEBAS-DE-ACEPTACION.md`. Hay dos caminos, y la decisión es del operador:

| Opción | Qué implica |
| --- | --- |
| Exponer MinIO | Publicar `9090:9000` y poner `LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT` con la URL pública. Suma un puerto expuesto. |
| Proxy para los medios | Enrutar las rutas de medios por el proxy inverso. Hay que probarlo. |

Mientras no se decida, el resto de la funcionalidad (trazas, costos, latencias)
**no depende de esto**.

## 9. Primer acceso

Continúa en `04-PRIMERA-CUENTA-Y-USUARIOS.md`.

## 10. Primer respaldo

Hazlo apenas funcione, **antes** de tocar nada:

```bash
chmod +x scripts/*.sh
./scripts/backup-langfuse.sh
```

El detalle está en `05-RESPALDOS-Y-RESTAURACION.md`.

## 11. Problemas frecuentes en la instalación

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| El web no levanta | Migraciones en curso | Esperar 3 min y revisar `docker compose logs langfuse-web` |
| `web` reinicia en bucle | `NEXTAUTH_URL` ausente o inválida | Revisar el `.env` |
| El worker no levanta | ClickHouse o Postgres no están sanos | `docker compose ps` y revisar healthchecks |
| Falla la autenticación de la interfaz | `NEXTAUTH_SECRET` vacío | Generarlo y reiniciar |
| Faltan tablas en Postgres | Postgres con datos viejos | Restaurar un respaldo o partir de cero |
| El navegador no abre la instancia | Cortafuegos o proxy mal configurado | `sudo ufw status` y revisar Caddy |

## 12. Diferencias con Coolify

Las diferencias están en `02-INSTALACION-COOLIFY.md`. El camino de este
documento es el recomendado para Hefesto: control total del host y del proxy.