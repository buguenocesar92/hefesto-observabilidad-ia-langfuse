# Ejemplo 2 — Conectar Dify (kit Hefesto) con Langfuse

> **ESTO ES UNA DEMOSTRACION.** Muestra cómo se relacionan los dos kits de
> Hefesto. No es código de Dify ni código de Langfuse: es el procedimiento para
> **UNIR** dos instalaciones que ya existen.
>
> Todo lo marcado **VERIFICADO** proviene de la documentación oficial, citada al
> final. Lo marcado **DEMOSTRACION** es el camino que propone Hefesto y **no se
> ejecutó** en este entorno.

---

## 1. Para quién es esta receta

Para el caso más probable en Hefesto: el cliente ya tiene una aplicación creada
con el kit [`hefesto-dify-ia-aplicada`](../../hefesto-dify-ia-aplicada/) y ahora
quiere saber cuánto gasta y dónde se demora.

**Relación entre los dos kits** (VERIFICADO): Dify se integra de forma nativa
con Langfuse. Se usan **juntos o por separado**:

| | Kit Dify | Kit Langfuse (este) |
| --- | --- | --- |
| Qué hace | **Construye** la aplicación: chatbots, RAG, agentes | **Mide** lo que ya pasó: trazas, costos, latencia |
| ¿Ejecuta modelos? | Sí, a través de los proveedores | **No.** No ejecuta ni entrena modelos |
| Relación | Orquesta | Observa |

Dify y Langfuse se pueden usar juntos, pero también **por separado**: Langfuse
observa cualquier aplicación, aunque no sea Dify y aunque el proveedor de modelos
sea otro. Si el cliente ya usa otra plataforma, este kit sigue sirviendo.

> No confundir: **Langfuse no es un producto de IA.** Es la capa de
> observabilidad. Ver la sección "Qué es y qué no es" del `README.md`.

---

## 2. El camino nativo (recomendado) — VERIFICADO

Dify trae una integración oficial con Langfuse. **No hay que escribir código.**

### Paso 1 — Tener el proyecto y las claves en Langfuse

En la interfaz de Langfuse, crea un proyecto y copia las claves desde los
ajustes del proyecto. Ver `docs/04-PRIMERA-CUENTA-Y-USUARIOS.md`.

### Paso 2 — Configurar Dify

Según la documentación oficial de la integración:

1. En Dify, ve a los ajustes de **Monitoring** (Monitoreo) de tu aplicación.
2. Añade Langfuse desde el menú **Third-party LLMOps provider**.
3. Pega las claves del paso 1.
4. Invoca la aplicación de Dify desde la interfaz o por la API para empezar a
   capturar trazas.

Fuente: <https://langfuse.com/integrations/no-code/dify>

### Paso 3 — Comprobar

Invoca la aplicación y revisa la lista de trazas en Langfuse. Deberías ver una
traza nueva por cada invocación.

---

## 3. Qué datos viajan de Dify a Langfuse

**VERIFICADO.** La integración nativa mapea estos campos de forma automática:

| Dify | Langfuse |
| --- | --- |
| `user` | `userId` |
| `message_id` | `trace_id` |
| `conversation_id` | `sessionId` |
| nombre de la aplicación | `trace.name` |
| tipo de aplicación y tipo de modelo | `tags` |

Lo relevante para Hefesto, en la práctica:

- **`conversation_id` → `sessionId`** es lo que permite ver toda una
  conversación como una sesión y no como trazas sueltas. Es el nexo que le
  importa al cliente cuando pregunta "¿cuánto gastó **esta** conversación?".
- **`user` → `userId`** permite el desglose de costo por usuario.

---

## 4. Lo que esta integración NO cubre

Honestidad sobre los límites, para no prometer de más:

- **No reemplaza la instrumentación del backend.** Mide lo que Dify ejecuta. Si
  el cliente tiene lógica propia fuera de Dify, esa parte sigue sin medirse.
- **Los costos dependen de los precios conocidos.** Ver
  `ejemplos/01-INSTRUMENTACION-APLICACION-EXISTENTE.md`, sección 6: si el modelo
  no tiene definición de precio, el costo no aparece.
- **Es una integración de Dify, no un conector de Hefesto.** No hay código
  propio de Hefesto acá: se usa la funcionalidad nativa de Dify.

---

## 5. Gestión de prompts entre ambos (opcional) — VERIFICADO

Existe un **plugin mantenido por la comunidad** para usar prompts gestionados y
versionados en Langfuse dentro de las aplicaciones de Dify:

- Repositorio: <https://github.com/gao-ai-com/dify-plugin-langfuse>

Qué aporta: obtener prompts desde Langfuse, buscarlos con filtros y actualizarlos
creando versiones nuevas con etiquetas.

**Honestidad:** este plugin lo mantiene la comunidad, **no Hefesto y no
Langfuse**. Antes de ofrecerlo a un cliente conviene revisarlo y probar que
funciona con las versiones concretas de Dify y Langfuse instaladas. Este kit no
lo incluye ni lo prueba.

---

## 6. Cómo se verifica en la práctica (propuesta de Hefesto)

**DEMOSTRACION.** Secuencia de comprobación que Hefesto puede ejecutar al
entregar:

1. Levantar Dify y Langfuse, ambos con sus kits.
2. En Dify, crear una aplicación mínima: un chatbot que diga hola.
3. Invocarla tres veces.
4. En Langfuse, confirmar que aparecen **tres trazas**.
5. Abrir una y revisar que se ven: el modelo usado, los tokens y el costo.
6. Conectar los filtros por `sessionId` y confirmar que las tres caen en la misma
   sesión.
7. Registrar el tiempo que tardó cada invocación y compararlo con la latencia que
   muestra Langfuse.

Si alguna de estas comprobaciones falla, el problema más probable es que las
claves estén mal pegadas o que la URL de Langfuse no sea alcanzable desde la red
de Dify. Esta secuencia **está pendiente de ejecutarse**: ver
`docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## 7. Costo de esta integración

Al integrate, Dify envía cada invocación a Langfuse. Eso significa:

- tráfico de red adicional desde el servidor de Dify;
- las conversaciones del usuario quedan almacenadas en la instancia de Langfuse
  (trazas, entradas y salidas).

Si el cliente maneja datos sensibles, conviene revisar qué queda guardado y por
cuánto tiempo **antes** de habilitar la integración, no después. Ver la sección
"El costo de instrumentar" en
`ejemplos/01-INSTRUMENTACION-APLICACION-EXISTENTE.md`.

---

## 8. Fuentes

- Integración nativa Dify: <https://langfuse.com/integrations/no-code/dify>
- Costos y modelos: <https://langfuse.com/docs/observability/features/token-and-cost-tracking>
- Plugin de prompts (comunidad): <https://github.com/gao-ai-com/dify-plugin-langfuse>

**Recordatorio:** la sección 6 es una propuesta de verificación de Hefesto y
**no se ejecutó** en este entorno.