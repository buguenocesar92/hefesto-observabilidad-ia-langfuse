# 10 — Licencias y fuentes

Este documento lista las licencias de cada componente, con el enlace a la fuente
oficial, y aclara las obligaciones reales que generan.

> **Aviso:** este es un resumen técnico leído durante la preparación del kit, con
> las fuentes enlazadas. **No es una opinión legal.** Para un cliente con dudas
> de cumplimiento, corresponde una revisión legal.

---

## 1. Langfuse — núcleo MIT, empresa por separado

**Fuente oficial:**
- Núcleo: <https://github.com/langfuse/langfuse/blob/v4.63.0/LICENSE>
- Empresa: <https://github.com/langfuse/langfuse/blob/v4.63.0/ee/LICENSE>

### Cómo está dividido

| Capa | Dónde | Licencia |
| --- | --- | --- |
| Núcleo | Todo lo que está **fuera** de `ee/`, `web/src/ee/` y `worker/src/ee/` | **MIT Expat** |
| Empresa | `ee/`, `web/src/ee/`, `worker/src/ee/` | **Enterprise License** de Langfuse |

Titular de los derechos de autor en ambos archivos: **ClickHouse, Inc.**
(2023-2026). Langfuse pasó a formar parte de ClickHouse; **eso no cambia las
licencias**.

### Qué obliga realmente la licencia MIT

La licencia MIT Expat es de las más permisivas que existen. Obligaciones reales:

| Obliga | No obliga |
| --- | --- |
| Incluir el aviso de copyright y el texto de la licencia al distribuir el software | Publicar el código de las aplicaciones que lo consumen |
| — | Copiar la licencia a obras derivadas de Langfuse en sí | 
| — | Pagar a Langfuse |
| — | Usarlo con fines comerciales |

En la práctica: **se puede instalar y usar comercialmente el núcleo sin pagar
nada a Langfuse y sin publicar nada.** No hay copyleft.

### Lo que NO se puede hacer sin licencia

Usar los archivos de `ee/` **sin** un acuerdo y licencia Enterprise vigente. El
texto de `ee/LICENSE` es explícito: el software enterprise "may only be used, if
you... have agreed to, and are in compliance with, the applicable agreement
governing the use of the Software, as agreed between you and Langfuse GmbH or
ClickHouse, Inc." y "you otherwise have a valid Langfuse Enterprise License".

**En la práctica con este kit:** se instala el núcleo MIT. Las funciones de
empresa (retención automática, SSO empresarial, SCIM, RBAC granular,
exportaciones programadas, registro de auditoría) **no están disponibles sin
licencia**. Ver `08-SERVICIOS-COMERCIALES.md`.

---

## 2. Componentes de terceros

### PostgreSQL

- **Licencia:** PostgreSQL License, similar a BSD, permisiva.
- **Fuente:** <https://www.postgresql.org/about/licence/>
- **Obligaciones:** mantener el aviso de licencia. Sin copyleft.

### ClickHouse

- **Licencia:** Apache License 2.0.
- **Fuente:** <https://github.com/ClickHouse/ClickHouse/blob/master/LICENSE>
- **Obligaciones:** mantener los avisos de licencia y de propiedad. Si se
  modifica y se distribuye, hay que indicar los cambios.
- **Uso en este kit:** es el almacén de eventos. Obligatorio.

### Redis

- **Licencia:** **cambió con la versión 7.4.** Hasta la 7.2 era BSD de 3
  cláusulas; desde la 7.4 es una triple licencia entre **RSALv2**, **SSPLv1** y
  **AGPLv3**.
- **Fuente:** <https://redis.io/legal/licenses/>
- **Qué usa este kit:** el digest fijado (`VERSION.md`) corresponde al estado
  anterior al cambio, es decir, **BSD**.
- **Obligaciones:** ninguna relevante, porque Redis **no se distribuye** dentro
  del producto del cliente: se ejecuta como infraestructura. No hay obligación
  de ofrecer su código fuente.
- **Aviso a Hefesto:** antes de firmarle un despliegue a un cliente, verificar
  el digest efectivamente desplegado. Un `pull` posterior podría traer una
  versión con licencia más restrictiva.

### MinIO

- **Licencia:** AGPL v3 en el proyecto MinIO; la imagen que usa este kit la
  mantiene Chainguard.
- **Fuente:** <https://github.com/minio/minio/blob/master/LICENSE>
- **Lectura prudente:** AGPL obliga a publicar el código **del programa Agpl**, no
  el de quien lo ejecuta como servicio separado. MinIO se ejecuta como proceso
  aislado, no se modifica ni se vincula al producto del cliente, por lo que en
  principio no se origina esa obligación.
- **Atención:** esta es una lectura del modelo AGPL, **no un dictamen legal**.
  Si el cliente tiene dudas, que lo revise con su abogado.

---

## 3. Archivos de Hefesto Studio

| Archivo | Licencia |
| --- | --- |
| `compose.yaml` | MIT (Hefesto Studio) |
| `.env.example` | MIT (Hefesto Studio) |
| `scripts/backup-langfuse.sh` | MIT (Hefesto Studio) |
| `scripts/restore-langfuse.sh` | MIT (Hefesto Studio) |
| `README.md`, `VERSION.md`, `LICENCIAS.md` | MIT (Hefesto Studio) |
| `docs/*.md` | MIT (Hefesto Studio) |
| `ejemplos/*.md` | MIT (Hefesto Studio), salvo indicación en contrario |

Hefesto Studio es autor **solo** de esta capa de despliegue. **No** es autor de
Langfuse, PostgreSQL, ClickHouse, Redis ni MinIO.

---

## 4. Qué es de upstream y qué es de Hefesto

| Parte | Origen |
| --- | --- |
| Aplicación Langfuse | Upstream, <https://github.com/langfuse/langfuse>, MIT (núcleo) |
| Imágenes Docker | Upstream y terceros, fijadas por digest en `compose.yaml` |
| `compose.yaml` de este kit | **Hefesto.** Adaptación del compose oficial v4.63.0 |
| `.env.example` | **Hefesto.** Documentado a partir del compose y la configuración oficial |
| Scripts de respaldo | **Hefesto.** Código propio |
| Documentación de `docs/` | **Hefesto.** Redactada desde fuentes oficiales citadas |
| Recetas de `ejemplos/` | **Hefesto.** Marcadas como demostración |

> **Este kit es un kit de despliegue**, no el código original de Langfuse. Solo
> apunta a imágenes Docker construidas por upstream. No incluye código de la
> aplicación del cliente.

---

## 5. Datos y cumplimiento

Un punto que no es una licencia pero conviene dejar por escrito:

Al instrumentar una aplicación, **los prompts y las respuestas viajan al servidor
de Langfuse**. Eso significa que datos del usuario final quedan almacenados en la
instancia del cliente. Las certificaciones **SOC 2** e **ISO 27001** de Langfuse
corresponden a los **planes de nube**, no a la edición libre autoalojada.

Ver `08-SERVICIOS-COMERCIALES.md`.

---

## 6. Fuentes completas

**Langfuse**
- Releases: <https://github.com/langfuse/langfuse/releases>
- Núcleo: <https://github.com/langfuse/langfuse/blob/v4.63.0/LICENSE>
- Empresa: <https://github.com/langfuse/langfuse/blob/v4.63.0/ee/LICENSE>
- Compose del tag v4.63.0: <https://github.com/langfuse/langfuse/blob/v4.63.0/docker-compose.yml>
- Documentación: <https://langfuse.com/docs>
- Autoalojado: <https://langfuse.com/self-hosting>

**Terceros**
- PostgreSQL: <https://www.postgresql.org/about/licence/>
- ClickHouse: <https://github.com/ClickHouse/ClickHouse/blob/master/LICENSE>
- Redis: <https://redis.io/legal/licenses/>
- MinIO: <https://github.com/minio/minio/blob/master/LICENSE>
- Chainguard: <https://www.chainguard.dev/>