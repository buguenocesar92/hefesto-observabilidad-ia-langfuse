# 04 — Primera cuenta, usuarios y organization

Procedimiento verificado contra la documentación oficial de autoalojado de
Langfuse. Todas las rutas de la interfaz son las de **v4.63.0**.

---

## 1. Antes de abrir la instancia al mundo

Hazlo **antes** de exponer el dominio. Es el orden correcto y evita la
ventana de tiempo en que cualquiera puede crearse una cuenta.

En el `.env`:

```bash
AUTH_DISABLE_SIGNUP=true
LANGFUSE_TRUSTED_PROXY_COUNT=1
```

```bash
docker compose up -d
```

> `AUTH_DISABLE_SIGNUP=true` **impide crear cuentas nuevas**. Solo pueden entrar
> los usuarios que ya existen en la base de datos.
>
> Esto **no** lo hace `LANGFUSE_DISABLE_SIGNUP_ONBOARDING`, que solo omite el
> paso del formulario de novedades. Es una confusión habitual y grave.
>
> Verificado en: <https://langfuse.com/self-hosting/security/authentication-and-sso>

Comprueba que el registro quedó cerrado antes de seguir:

1. Abre una ventana de incógnito.
2. Entra a la URL de la instancia.
3. El enlace de registro debe estar ausente o rechazando.

---

## 2. Crear la primera cuenta

**VERIFICADO:** la instancia **no trae ninguna cuenta por defecto**. No existe
usuario ni contraseña administrador de fábrica. Hay que crearla.

Procedimiento recomendado por Hefesto:

1. Abre la URL de la instancia en un navegador.
2. Regístrate con el correo del cliente (o con tu correo de Hefesto, según
   corresponda a quién se le entrega la instancia).
3. Así se crea la **organización** y el **primer usuario** a la vez.

> Con `AUTH_DISABLE_SIGNUP=true`, esta es la única oportunidad de crear la
> cuenta inicial, porque el registro ya está cerrado. **Esto es lo esperado y
> así debe quedar.** Para dejar el registro abierto solo durante este paso,
> puedes poner temporalmente `AUTH_DISABLE_SIGNUP=false`, crear la cuenta y
> volver a `true` enseguida.

### Alternativa: inicialización sin interfaz

Para despliegues automatizados se puede crear la cuenta con variables
`LANGFUSE_INIT_*`. El detalle está en `03-VARIABLES-Y-COMO-OBTENERLAS.md`,
sección 5.

Hefesto prefiere el camino manual para una entrega a cliente: no deja la
*secret key* del proyecto escrita en el historial del despliegue.

---

## 3. Cerrar el registro: verificación explícita

Hazla y **anota el resultado**. Es una de las comprobaciones de
`07-PRUEBAS-DE-ACEPTACION.md`.

| Prueba | Resultado esperado |
| --- | --- |
| Ventana de incógnito, ir a la URL | El formulario de registro **no** aparece |
| Intentar registrarse con un correo nuevo | Se rechaza |
| Iniciar sesión con la cuenta ya creada | **Sí** entra |

---

## 4. Crear el proyecto y las claves de API

Este es el paso que el cliente va a necesitar para instrumentar sus aplicaciones.

1. Dentro de la organización, **Settings** → **Projects** → **New Project**.
2. Ponle un nombre descriptivo. Si el cliente tiene varios entornos, crea
   proyectos separados, por ejemplo `produccion` y `pruebas`. Aislar producción
   de pruebas es más barato que filtrar después.
3. Abre el proyecto y entra a **Settings** → **API Keys**.
4. Copia el **public key** (`pk-lf-...`) y el **secret key** (`sk-lf-...`).

El **secret key es una credencial**. Trátalo como una contraseña:

- no lo mandes por correo si puedes evitarlo;
- no lo pegues en un chat;
- no lo escribas en un documento que se comparta;
- entrégaselo al cliente por un canal seguro.

### Verificación de la clave

En la aplicación del cliente, con el SDK de Python v5:

```python
from langfuse import get_client

langfuse = get_client()
print("OK" if langfuse.auth_check() else "FALLO: revisa las claves y LANGFUSE_BASE_URL")
```

O desde la terminal, contra la instancia:

```bash
curl -s -u "pk-lf-TU_CLAVE:sk-lf-TU_CLAVE" \
  https://observabilidad.ejemplo.cl/api/public/projects
```

> `LANGFUSE_BASE_URL`, no `LANGFUSE_HOST`. Ver la sección 6 de este documento.

---

## 5. Modelo de permisos y quién ve qué

**VERIFICADO.** Esto es lo que hay que decirle al cliente con precisión, porque
es donde más se suele exagerar.

La estructura es:

```
Organización
 └── Equipos (equipos)
      └── Proyectos (projects)
```

Los permisos disponibles son **member** (miembro), **admin** (administrador) y
**owner** (propietario).

Puntos importantes y honestos:

- **Dentro de un proyecto, todos los miembros ven todo.** No hay permisos finos
  por traza ni por usuario. Quien entra al proyecto ve las conversaciones de
  todos los usuarios de la aplicación.
- **El control de acceso detallado (RBAC granular) es función de pago.**
- **La edición libre autoalojada no tiene aislamiento entre organizaciones**
  más allá de la separación por membresía en la base de datos.
- **No hay cumplimiento normativo certificado** en la edición libre. La
  certificación SOC 2 e ISO 27001 es de los planes de pago.

### Consecuencia práctica

Si el cliente guarda datos personales en los prompts (nombres, correos, historial
de conversaciones), **cualquier miembro del proyecto los puede ver**. Hay que
decírselo explícitamente antes de conectar una aplicación real.

### Enlaces públicos

Langfuse permite compartir una traza mediante un enlace. **VERIFICADO:** un
enlace público da acceso **de solo lectura a esa traza**, sin necesidad de
cuenta. Es decir: quien tenga el enlace puede leer su contenido.

Recomendación de Hefesto: no usar enlaces públicos con datos de clientes. Si se
comparte una traza con información sensible,_revise el contenido antes de
generar el enlace.

---

## 6. Problemas frecuentes

| Síntoma | Causa | Qué hacer |
| --- | --- | --- |
| No aparece el formulario de registro | `AUTH_DISABLE_SIGNUP=true` ya activo | Ver sección 2: es el comportamiento correcto |
| Crece y baja en un bucle | `NEXTAUTH_URL` no coincide con el dominio | Igualar las cadenas exactamente |
| "Se debe iniciar sesión con el mismo proveedor" | Se cambió de método de autenticación | Volver al original o habilitar vinculación de cuentas |
| "Olvidé mi contraseña" no llega | No hay SMTP configurado | Configurar `SMTP_CONNECTION_URL`, ver sección 7 |
| `auth_check()` devuelve `False` | Llave rotada o URL mal escrita | Revisar `LANGFUSE_BASE_URL` y regenerar la llave |

---

## 7. Recuperar una contraseña sin correo configurado

**VERIFICADO.** Si no hay SMTP, la documentación describe este procedimiento
manual sobre la base de datos:

1. Cambia el correo del usuario en la base agregándole un prefijo, por ejemplo
   `recuperado+` delante.
2. Así el usuario puede registrarse de nuevo con una contraseña nueva.
3. Reasigna las organizaciones al nuevo usuario, desde la tabla
   `organization_memberships`.
4. Elimina la cuenta antigua, desde la tabla `users`.

Antes de ejecutar esto sobre datos de cliente: **toma un respaldo**. Es una
operación que modifica datos de la aplicación.

---

## 8. Cómo crear usuarios después

Con el registro cerrado, un usuario nuevo **no puede self-servicio**. Las
formas son:

1. **Invitación desde la interfaz**: en la organización, inviting al usuario por
   correo. Nota: con `AUTH_DISABLE_SIGNUP=true` la documentación advierte que
   **también se bloquea a quienes recibieron una invitación y no tienen cuenta**,
   porque para ellos el registro es un alta nueva.
2. **Crear la cuenta primero con el registro abierto temporalmente**: activar
   `AUTH_DISABLE_SIGNUP=false`, crear las cuentas, volver a `true`.
3. **API de administración de organización**: permite aprovisionar usuarios de
   forma programática.

> La opción 3 es la adecuada para clientes con varios usuarios y es parte de las
> capacidades de administración. Revisar disponibilidad y licencia antes de
> comprometerla. Ver `08-SERVICIOS-COMERCIALES.md`.

---

## 9. Respaldo de las claves: la advertencia que hay que dar

**Las claves de API de Langfuse son credenciales.**

Si el cliente pierde el respaldo de PostgreSQL, **o** cambia `SALT`,
`ENCRYPTION_KEY` o `NEXTAUTH_SECRET`, las claves de API existentes dejan de
validar. En ese caso hay que:

1. Crear claves nuevas desde la interfaz.
2. **Actualizar las variables de entorno en cada aplicación instrumentada.**
3. Reiniciar esas aplicaciones.
4. Verificar que vuelven a aparecer trazas.

Es decir: **la instrumentación se rehace**. Por eso el respaldo de PostgreSQL
y los tres valores secretos se tratan con el mismo cuidado. Ver
`05-RESPALDOS-Y-RESTAURACION.md`.

---

## 10. Fuentes

- Autenticación y SSO autoalojado: <https://langfuse.com/self-hosting/security/authentication-and-sso>
- Inicialización sin interfaz: <https://langfuse.com/self-hosting/administration/headless-initialization>
- Roles y control de acceso: <https://langfuse.com/docs/administration/rbac>
- SDK y variables del cliente: <https://langfuse.com/docs/observability/sdk/overview>