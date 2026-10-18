# Ejemplo 1 — Instrumentar una aplicación que ya existe (Python + OpenAI)

> **ESTO ES UNA DEMOSTRACION.** Es una receta para adaptar a una aplicación
> real. **No es una aplicación de Hefesto** y no se entrega como producto.
> Copia los fragmentos, adáptalos y pruébalos en tu propio código.
>
> Todo lo que aparece en este documento es **DEMOSTRACION** o **VERIFICADO**.
> Se indica cuál es cuál en cada sección.

---

## 1. Qué vas a obtener

Tu aplicación sigue funcionando igual, pero además deja registro en Langfuse de:

- cada llamada al modelo (entrada, salida, modelo, tokens);
- el costo estimado de cada llamada;
- la latencia;
- el error, si la llamada falla;
- a qué usuario y a qué conversación corresponde.

Si algo falla en Langfuse, **la aplicación no se cae**: el SDK captura los
errores internamente y los registra.

---

## 2. Lo que necesitas

| Elemento | Detalle |
| --- | --- |
| Servidor Langfuse | Desplegado con este kit. Ver `docs/01-INSTALACION-DOCKER.md`. |
| Claves de API | Del proyecto en Langfuse. Ver `docs/04-PRIMERA-CUENTA-Y-USUARIOS.md`. |
| SDK de Python | `langfuse`, versión **v5** (VERIFICADO: requiere Langfuse >= v4.59.0) |
| Tus claves del proveedor | Las que ya usa tu aplicación. Langfuse **no** las reemplaza. |

### Punto clave: Langfuse no es el modelo

Langfuse **no ejecuta modelos ni los entrena**. No es una plataforma de IA.
Tu aplicación sigue hablando con OpenAI, Anthropic, Google o el proveedor que
ya uses. Langfuse se para al lado y observa. Este kit es el complemento de
[Dify (kit `hefesto-dify-ia-aplicada`)](../../hefesto-dify-ia-aplicada/), que sí
construye aplicaciones: **Dify construye la aplicación, Langfuse la mide.**

---

## 3. Instalación

```bash
pip install langfuse openai
```

> **VERIFICADO:** el SDK de Python v5 solo usa la API pública v4 y requiere un
> servidor Langfuse **>= v4.59.0**. Este kit instala v4.63.0, que cumple.
> Fuente: <https://langfuse.com/docs/observability/sdk/overview>

---

## 4. Variables de entorno del cliente

Estas **no son las variables del servidor**. Van en la aplicación que quieres
observar, no en el `.env` de Langfuse.

```bash
# .env de TU APLICACION. Valores de ejemplo falsos.
LANGFUSE_PUBLIC_KEY=pk-lf-CAMBIAR-clave-publica-de-ejemplo
LANGFUSE_SECRET_KEY=sk-lf-CAMBIAR-clave-secreta-de-ejemplo
LANGFUSE_BASE_URL=https://observabilidad.ejemplo.cl
```

> **OJO, nombre cambiado.** La documentación actual usa **`LANGFUSE_BASE_URL`**.
> Muchas guías viejas y tutoriales usan `LANGFUSE_HOST`. Con los SDK v5 / v6
> la variable correcta es `LANGFUSE_BASE_URL`. Si tu código usa `LANGFUSE_HOST`
> y no trazas nada, probablemente sea eso.
>
> **VERIFICADO:** <https://langfuse.com/docs/observability/sdk/overview>

| Variable | Obligatoria | Qué es |
| --- | --- | --- |
| `LANGFUSE_PUBLIC_KEY` | Sí | Identifica el proyecto. Va en el servidor. |
| `LANGFUSE_SECRET_KEY` | Sí | **Credencial.** Autoriza la escritura de trazas. |
| `LANGFUSE_BASE_URL` | Sí en autoalojado | La URL de tu instancia, sin barra final. |

### La clave secreta no viaja al navegador

**VERIFICADO:** los SDK de trazas están hechos para código de servidor. Autentican
con la clave secreta, que **nunca debe llegar al navegador ni a una app móvil**.
Instrumenta el backend que llama al modelo.

Si necesitas enviar desde el frontend, usa `@langfuse/browser` con la clave
pública **solo** para registrar puntuaciones (por ejemplo, un me gusta). No
crea trazas y no acepta la clave secreta.

---

## 5. Receta mínima con FastAPI (DEMOSTRACION)

```python
# main.py — DEMOSTRACION. Adapta esto a tu aplicacion.
import os
from fastapi import FastAPI
from openai import OpenAI

from langfuse import get_client

app = FastAPI()
openai_client = OpenAI()  # usa OPENAI_API_KEY del entorno

# El cliente lee LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY / LANGFUSE_BASE_URL
# desde el entorno. Tambien se puede pasar como argumento.
langfuse = get_client()


@app.get("/preguntar")
def preguntar(consulta: str, usuario: str = "anonimo"):
    # Crea una traza y, dentro, una "generation" que representa la llamada
    # al modelo. El bloque anidado mantiene la relacion padre-hijo.
    with langfuse.start_as_current_observation(
        as_type="span", name="pregunta-usuario"
    ) as traza:
        # These datos se copian a todas las observaciones hijas.
        traza.update(metadata={"origen": "api-web"})

        with langfuse.start_as_current_observation(
            as_type="generation",
            name="respuesta-openai",
            model="gpt-4o-mini",
            input=[{"role": "user", "content": consulta}],
        ) as generacion:
            try:
                respuesta = openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": consulta}],
                )
            except Exception as exc:
                # Marcar el error hace que la traza sea navegable en la UI.
                generacion.update(output=str(exc), level="ERROR", status_message=str(exc))
                raise

            texto = respuesta.choices[0].message.content

            # ESTE es el fragmento que cuesta dinero: es el que registra el uso.
            # Los buckets deben ser EXCLUYENTES entre si.
            generacion.update(
                output=texto,
                usage_details={
                    "input": respuesta.usage.prompt_tokens,
                    "output": respuesta.usage.completion_tokens,
                },
            )

            return {"respuesta": texto}


@app.on_event("shutdown")
def cerrar():
    # Imprescindible en procesos cortos (scripts, jobs, funciones lambda).
    langfuse.flush()
```

### Sobre los `usage_details`: la parte que más se equivoca

**VERIFICADO:** <https://langfuse.com/docs/observability/features/token-and-cost-tracking>

Langfuse trata cada clave de `usage_details` como un **balde separado y sin
solapamiento**:

- `input` **excluye** cualquier `input_*` (como `input_cached_tokens`).
- `output` **excluye** cualquier `output_*`.
- `total` es la suma de los baldes, no un balde.

Si los baldes se solapan, el costo que muestra Langfuse **sobreestima** lo que
el proveedor cobró de verdad. La documentación es explícita sobre esto.

---

## 6. ¿De dónde salen los costos?

**VERIFICADO.** Langfuse guarda dos cosas por cada generación:

1. **Uso**: cuántos tokens (u otras unidades) se consumieron.
2. **Costo**: cuántos dólares, desglosado por tipo de uso.

Cada una puede llegar de dos maneras:

| | Ingestado | Inferido |
| --- | --- | --- |
| Qué es | Lo manda tu aplicación en `usage_details` | Lo calcula Langfuse |
| Cuándo | El proveedor devuelve el conteo real | No hay conteo, pero hay precio conocido |
| Prioridad | **Gana el ingestionado** | Se usa solo si no llegó nada |

El costo **inferido** sale de las **definiciones de modelo**: Langfuse trae una
lista de precios para modelos populares de OpenAI, Anthropic y Google, y puede
calcular tokens con un tokenizador si el modelo tiene uno.

### Casos donde el costo NO aparece

- **Modelos de razonamiento** (familia `o1`): Langfuse no puede inferir el costo
  sin que le mandes el conteo de tokens. Hay que enviarlo.
- **Modelos propios o de gateway**: agrega tu propia definición de modelo con
  `POST /api/public/models`. Las definiciones propias **tienen prioridad** sobre
  las de Langfuse.
- **Si cambias una definición de modelo**, el precio nuevo se aplica **solo a las
  trazas nuevas**, no a las ya guardadas.

Esto es relevante para Hefesto: **es la función que el cliente va a comprar**,
y tiene estos límites conocidos. Ver `docs/08-SERVICIOS-COMERCIALES.md`.

---

## 7. El costo de instrumentar (sea honesto con esto)

Instrumentar **no es gratis**, y conviene decírselo al cliente antes de hacerlo:

- **Llamadas de red adicionales.** Cada traza viaja desde tu servidor a Langfuse.
- **Latencia.** Los SDK v5 y v6 son asíncronos y la documentación indica que
  Langfuse agrega muy poca latencia, pero no es cero: es tráfico real que sale
  de tu servidor.
- **Salida de datos.** Los prompts y respuestas **viajan al servidor Langfuse**.
  Si la información es sensible, eso es una consideración de cumplimiento, no un
  detalle técnico.
- **Volumen.** Las trazas crecen sin límite en la edición libre autoalojada.
  El disco se llena si nadie mira el crecimiento.

Buenas prácticas para reducir el costo, todas **VERIFICADAS**:

- El SDK se ejecuta en segundo plano y **no puede romper tu aplicación**: los
  errores del SDK se capturan y se registran, no se propagan.
- Llama a `flush()` solo en procesos cortos. En un servidor web de larga duracion
  no hace falta en cada request.

---

## 8. Comprobar que funciona (VERIFICADO)

**VERIFICADO:** los endpoints de salud son estos, tomados de la documentacion de
autoalojado.

```bash
# Estado de salud del servicio web
curl -s https://observabilidad.ejemplo.cl/api/public/health

# Sonda de disposibilidad (indica si puede atender trazas)
curl -s https://observabilidad.ejemplo.cl/api/public/ready
```

En el lado de la aplicación, la forma más simple de confirmar que las credenciales
funcionan, con el SDK de Python v5:

```python
from langfuse import get_client

langfuse = get_client()
if langfuse.auth_check():
    print("Cliente Langfuse autenticado y listo.")
else:
    print("Falló la autenticación. Revisa PUBLIC_KEY, SECRET_KEY y BASE_URL.")
```

Si `auth_check()` devuelve `False`, el problema casi siempre es la URL mal
escrita o una llave rotada. En ese caso `langfuse.flush()` sigue funcionando y
las trazas quedan en la cola local.

---

## 9. Resolver problemas

| Síntoma | Causa probable | Qué revisar |
| --- | --- | --- |
| No aparece ninguna traza | Credenciales o URL | `LANGFUSE_BASE_URL` (no `LANGFUSE_HOST`), llave, estado del servidor |
| `auth_check()` da `False` | Llave rotada o URL mal | Regenerar la llave en la interfaz del proyecto |
| Las trazas se pierden al cerrar | Falta `flush()` | Añadir `flush()` al `shutdown` |
| El costo aparece en 0 | Modelo sin definición de precio | Agregar definición de modelo propia, o enviar `usage_details` |
| El costo está inflado | Baldes de uso solapados | Revisar que `input` excluya `input_*` |

### Un detalle importante sobre el respaldo

Las **claves de API de Langfuse son credenciales**. Si se pierde el respaldo de
PostgreSQL, o se cambian `SALT` / `ENCRYPTION_KEY` / `NEXTAUTH_SECRET`, las
claves existentes dejan de validar y **hay que rehacer la instrumentación de
todas las aplicaciones del cliente**. Ver
`docs/05-RESPALDOS-Y-RESTAURACION.md`.

---

## 10. Fuentes

- SDK de Python y JS/TS: <https://langfuse.com/docs/observability/sdk/overview>
- Tokens y costos: <https://langfuse.com/docs/observability/features/token-and-cost-tracking>
- Endpoints de salud: <https://langfuse.com/self-hosting/configuration/health-readiness-endpoints>
- Instrumentacion: <https://langfuse.com/docs/observability/sdk/instrumentation>

**Recordatorio:** este ejemplo es una demostración. Fue escrito contra la
documentación oficial verificada, pero **no se ejecutó** en este entorno. Está
en la lista de pendientes de `docs/07-PRUEBAS-DE-ACEPTACION.md`.