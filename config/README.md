# config/ — sin uso en este kit

Esta carpeta está **vacía a propósito**, y el motivo conviene dejarlo escrito.

En Hefesto, `config/` aloja archivos de configuración auxiliares: plantillas de
nginx, certificados de ejemplo, archivos de entrypoint propios del kit. El
[`hefesto-dify-ia-aplicada`](../../hefesto-dify-ia-aplicada/) sí tiene varios,
porque necesita un proxy interno para los modelos locales.

**El kit de Langfuse no los necesita:**

- La configuración de los seis servicios está completa y explícita en
  `compose.yaml`, incluido el directorio de Conf con las variables de entorno.
- El proxy inverso (Caddy, nginx o Traefik) queda **en el servidor del cliente**,
  fuera de este kit. En `docs/01-INSTALACION-DOCKER.md`, sección 8, está la
  configuración de Caddy como ejemplo.
- No hay certificados de ejemplo: el certificado lo emite Let's Encrypt en el
  servidor, no se versiona.

Se deja la carpeta en lugar de eliminarla para que quede constancia de que la
ausencia es una decisión y no un olvido.