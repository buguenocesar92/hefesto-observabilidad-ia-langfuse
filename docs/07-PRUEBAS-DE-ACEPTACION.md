# 07 — Pruebas de aceptación

> **Estado del kit: `kit preparado`.**
>
> No hay Docker, ni servidor, ni navegador en el entorno donde se preparó este
> kit. **Ninguna de las pruebas de la sección B se ejecutó.** La sección A
> contiene verificaciones que sí se hicieron, contra fuentes oficiales.
>
> Este documento existe para que nadie confunda lo comprobado con lo supuesto.

---

## A. Verificado realmente en la preparación del kit

Estas comprobaciones **sí se ejecutaron** y su resultado es el que dice la tabla.

| # | Qué se comprobó | Cómo | Resultado |
| --- | --- | --- | --- |
| A1 | Versión estable más reciente de Langfuse | API de releases de GitHub, 2026-10-17 | **v4.63.0**, publicada 2026-10-16 |
| A2 | Licencia del núcleo | Lectura de `LICENSE` en el tag v4.63.0 | **MIT Expat**, titular ClickHouse, Inc. |
| A3 | Licencia de la capa de empresa | Lectura de `ee/LICENSE` en el tag v4.63.0 | **Enterprise License**, solo `ee/`, `web/src/ee/`, `worker/src/ee/` |
| A4 | Topología de servicios | Lectura del `docker-compose.yml` del tag v4.63.0 | 6 servicios: web, worker, ClickHouse, PostgreSQL, Redis, MinIO |
| A5 | ClickHouse es obligatorio | Documentación de infraestructura | No se puede autoalojar sin ClickHouse |
| A6 | Versión mínima de PostgreSQL | Documentación de infraestructura | Mínimo **15**, recomendado **16**; upstream usa 17 |
| A7 | Versión de ClickHouse | Compose oficial y documentación | Compose fija **25.12**; la documentación recomienda 26.4 |
| A8 | Digest de `langfuse/langfuse:4` | API de manifiesto de Docker Hub | `sha256:67f48d1...` |
| A9 | Digest de `langfuse/langfuse-worker:4` | API de manifiesto de Docker Hub | `sha256:ca32a8fb...` |
| A10 | Digest de `clickhouse-server:25.12` | API de manifiesto de Docker Hub | `sha256:8a790dd3...` |
| A11 | Digest de `postgres:17` | API de manifiesto de Docker Hub | `sha256:2d2b8998...` |
| A12 | Digest de `redis:7` | API de manifiesto de Docker Hub | `sha256:4fa24486...` |
| A13 | Digest de `cgr.dev/chainguard/minio` | Intento de resolución del manifiesto | **NO SE PUDO.** El registro responde **HTTP 401** y exige token OIDC |
| A14 | Variable que cierra el registro | Documentación de autenticación autoalojada | **`AUTH_DISABLE_SIGNUP=true`** |
| A15 | `LANGFUSE_DISABLE_SIGNUP_ONBOARDING` | Documentación de configuración | Solo omite el formulario de novedades. **No cierra el registro** |
| A16 | Variable de URL en los SDK | Documentación del SDK | **`LANGFUSE_BASE_URL`**, no `LANGFUSE_HOST` |
| A17 | Versión mínima de SDK | Documentación del SDK | Python v5 y JS/TS v6 requieren servidor >= v4.59.0 |
| A18 | Origen de los costos | Documentación de costos | Definiciones de modelo; el uso ingestado tiene prioridad |
| A19 | Límites de la edición libre | Página de precios y documentación de retención | **Sin límites** de eventos, trazabilidad o retención en autoalojado |
| A20 | Retención automática | Documentación de retención | Sin política, los datos se guardan **indefinidamente** |
| A21 | Validación sintáctica del compose | Analizador YAML | **Correcto**: 6 servicios, 5 volúmenes |
| A22 | Puertos publicados en el compose | Lectura del `compose.yaml` | **Solo uno**: `127.0.0.1:3000` |
| A23 | Sintaxis de los scripts | `bash -n` sobre ambos scripts | **Sin errores de sintaxis** |
| A24 | Estructura del kit | Comparación con el contrato | Completa |

---

## B. Pendiente: nada de esto se ha ejecutado

Cada línea requiere Docker, un servidor o un navegador. **Ninguna se hizo.**

### B1 — Despliegue

- [ ] `docker compose pull` baja las cinco imágenes fijadas por digest.
- [ ] `docker compose up -d` levanta los seis servicios.
- [ ] Todos los servicios quedan en estado healthy o running.
- [ ] El servicio web registra "Ready" en un tiempo razonable.
- [ ] `curl http://127.0.0.1:3000/api/public/health` responde.
- [ ] `curl http://127.0.0.1:3000/api/public/ready` responde.
- [ ] El primer arranque tarda unos 3 minutos, como advierte upstream.

### B2 — Puertos y aislamiento

- [ ] `ss -tlnp` muestra **solo** el puerto 3000 en `127.0.0.1`.
- [ ] No hay ningún listener en `0.0.0.0` para 5432, 6379, 8123, 9000, 9090, 9091
      ni 3030.
- [ ] Desde otra máquina de la red, no se alcanza PostgreSQL, Redis,
      ClickHouse ni MinIO.

### B3 — Autenticación

- [ ] Con `AUTH_DISABLE_SIGNUP=true`, el formulario de registro **no aparece**.
- [ ] No se puede crear una cuenta con un correo nuevo.
- [ ] Se puede iniciar sesión con la cuenta creada previamente.
- [ ] `langfuse.auth_check()` devuelve verdadero con las claves del proyecto.

### B4 — Instrumentación y costos

- [ ] Una aplicación instrumentada envía trazas que aparecen en la interfaz.
- [ ] La traza muestra modelo, tokens de entrada y de salida.
- [ ] La traza muestra **costo estimado**.
- [ ] Varias invocaciones de una misma conversación caen en el mismo `sessionId`.
- [ ] Un modelo sin definición de precio muestra costo en cero, como advierte la
      documentación.

### B5 — Medios y MinIO

- [ ] Una imagen adjunta a una traza **se visualiza** en el navegador de un
      usuario remoto.
- [ ] Si no se visualiza, queda confirmado que hace falta exponer MinIO o enrutar
      las rutas de medios por el proxy. **Este es el punto más probable de fallar
      con este compose**, porque MinIO queda atado a `127.0.0.1`.

### B6 — Respaldo

- [ ] `backup-langfuse.sh` genera `postgres.dump`, `clickhouse.tar.gz` y
      `minio.tar.gz`.
- [ ] `MANIFESTO.estado` termina en `estado: completo`.
- [ ] `sha256sum -c MANIFESTO.sha256` devuelve OK para los tres artefactos.
- [ ] Los servicios quedan como estaban antes del respaldo.

### B7 — Restauración

- [ ] `restore-langfuse.sh` **se niega** si el destino ya tiene datos, sin
      `--force`.
- [ ] `restore-langfuse.sh` **se niega** si falta `estado: completo` en el
      manifiesto.
- [ ] `restore-langfuse.sh` **se niega** si un SHA-256 no calza.
- [ ] `restore-langfuse.sh` rechaza un tar con rutas `..` o absolutas.
- [ ] Tras restaurar, la aplicación inicia y muestra las trazas del respaldo.
- [ ] Los servicios quedan **detenidos** al terminar la restauración.
- [ ] La restauración completa funciona en un servidor limpio.

### B8 — Migración desde el respaldo

- [ ] `minio` se puede fijar por digest con el procedimiento de `VERSION.md`,
      sección 3.

### B9 — Coolify

- [ ] El compose despliega en Coolify y el dominio enruta correctamente.
- [ ] La publicación del puerto 3000 funciona con el proxy de Coolify.

### B10 — Cargas y límites

- [ ] Medir consumo de memoria y CPU con carga real del cliente.
- [ ] Medir crecimiento del volumen de ClickHouse por semana.
- [ ] Definir con el cliente una política de conservación de datos, porque **en la
      edición libre no hay retención automática**.

---

## C. Prueba mínima para declarar el kit en producción

Si hay que acotar el tiempo, estas seis comprobaciones son las que definen si el
servicio sirve o no:

1. **B2.1** — Solo el puerto 3000 está expuesto.
2. **B3.1** — El registro está cerrado.
3. **B4.1** — Llegan trazas desde la aplicación instrumentada.
4. **B4.3** — Las trazas muestran costo.
5. **B6.5** — El respaldo se completa y verifica.
6. **B7.6** — La restauración deja la instancia levantada y con datos.

Si alguna falla, no entregar en producción todavía.

---

## D. Cómo actualizar este documento

Cada vez que se ejecute una prueba de la sección B, márcala, anota la fecha y
quién la ejecutó, y mueve el estado del kit al que corresponda:

| Estado | Significado |
| --- | --- |
| `kit preparado` | Archivos escritos, sin Docker ni servidor |
| `validado localmente` | Comprobaciones reales ejecutadas en una máquina |
| `desplegado` | Corrió en un servidor real |
| `aceptado en servidor` | El cliente lo aceptó en producción |

Nunca marcar un estado que no se haya alcanzado.