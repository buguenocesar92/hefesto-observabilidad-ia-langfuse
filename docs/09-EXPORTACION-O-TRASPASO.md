# 09 — Exportación de datos y traspaso a otra plataforma

Este documento explica cómo sacan los datos del cliente de Langfuse, y —con
mucha claridad— **qué parte es una guía y qué parte sería un conector que hay
que construir**.

---

## 1. La distinción que hay que tener clara

> **Este kit NO incluye ningún conector a Odoo ni a ninguna otra plataforma.**

Lo que hay son **formatos de exportación** y **APIs públicas verificadas**. Un
CSV exportado **no es una sincronización automática**. Repetirlo porque es el
punto donde más se confunde al cliente:

| Es | No es |
| --- | --- |
| Un archivo que sale en un momento dado | Una integración que corre sola |
| Un respaldo para análisis o migración | Un traspaso continuo entre sistemas |
| Algo que Hefesto ejecuta a pedido | Una funcionalidad del producto |

Si el cliente pide "que los costos lleguen solos a Odoo", eso es **proyecto
 aparte**, con su propio alcance, presupuesto y pruebas. No viene incluido acá.

---

## 2. Exportación desde la interfaz

**VERIFICADO.** La mayoría de las tablas de Langfuse admiten exportación por
lotes. Se aplican **los mismos filtros que se ven en la tabla**, así que se puede
exportar un subconjunto (por ejemplo, solo las trazas de un usuario).

**Formatos disponibles: CSV y JSON.** Son dos, no más.

Detalles importantes:

| Aspecto | Comportamiento verificado |
| --- | --- |
| Filtros | Los de la tabla se aplican a la exportación |
| Columnas | Se exportan **todas**, sin importar la configuración de columnas de la vista. La personalización visual **no** afecta lo exportado |

Qué se puede exportar desde la interfaz:

- trazas y observaciones;
- puntuaciones (scores);
- conjuntos de datos y sus elementos;
- registros de experimentos.

### Procedimiento

1. Abrir la tabla correspondiente.
2. Aplicar los filtros que interesen.
3. Usar la acción de exportar.
4. Elegir CSV o JSON.
5. Revisar el archivo antes de entregárselo a alguien: **contiene el contenido
   real de los prompts y respuestas**, que puede incluir datos personales.

---

## 3. API pública y SDK

**VERIFICADO.** Para datos programáticos hay dos caminos:

| Camino | Para qué |
| --- | --- |
| **API pública / SDK** | Leer y escribir trazas, prompts, conjuntos de datos y puntuaciones desde código |
| **API de métricas** | Consultar **costos agregados** (tokens, costos, puntuaciones) con filtros, para herramientas de negocio |

La API de métricas es la que interesa para un tablero de costos: entrega cifras
agregadas y filtradas, no la conversación completa.

También hay una interfaz de línea de comandos oficial:

```bash
npx @langfuse/cli api <recurso> <accion>
```

Autenticación: las mismas claves del proyecto (`pk-lf-...` / `sk-lf-...`).

Referencia: <https://api.reference.langfuse.com>

---

## 4. Respaldo completo del servidor

Para un **traspaso de servidor** (migrar de una máquina a otra), lo que se usa es
el respaldo de `scripts/backup-langfuse.sh`, no una exportación desde la interfaz.

Ver `05-RESPALDOS-Y-RESTAURACION.md`.

> La exportación desde la interfaz **saca datos de negocio** (trazas, costos).
> El respaldo completo **saca además el estado**: usuarios, proyectos, claves de
> API, prompts. Son cosas distintas y para traspasar una instancia hay que usar
> el respaldo.

---

## 5. Traspaso de la instancia a otra plataforma

Distinguiendo lo verificado de lo que sería construcción:

### Lo que existe y se puede hacer hoy

| Necesidad | Camino | Estado |
| --- | --- | --- |
| Llevar la instancia a otro servidor | Respaldo + restauración | **Verificado.** Scripts incluidos |
| Sacar costos para un tablero | API de métricas | **Verificado** en documentación |
| Analizar las trazas en una hoja de cálculo | Exportar CSV | **Verificado** en documentación |
| Migrar a Langfuse Cloud | Exportar + importar | **No verificado** para este kit. Ver abajo |
| Traspasar a Odoo u otro ERP | — | **No existe. Hay que construirlo** |
| Migrar a otra herramienta de observabilidad | — | **No existe. Hay que construirlo** |

### Migración a Langfuse Cloud

La documentación **no se revisó** en profundidad para este kit. Si un cliente pide
salir de su servidor hacia la nube de Langfuse, hay que confirmar antes: qué se
puede exportar, con qué formato, y qué queda fuera. **No prometer que es
directo.**

### Traspaso a Odoo

Lo que haría falta, y **no existe**:

1. Extraer los costos agregados vía la API de métricas.
2. Mapear esas cifras a los campos de Odoo que el cliente use.
3. Escribir en Odoo con su API.
4. Programar la ejecución y manejar los errores.

**Eso es un conector y es un proyecto con horas asociadas.** Este kit no lo
incluye. Si el cliente lo necesita, se cotiza aparte.

### Migrar a otra herramienta de observabilidad

Cada herramienta tiene su propio formato. Langfuse exporta en **CSV y JSON**, que
es un punto de partida razonable, pero **no hay garantía de que el mapeo sea
directo**. Hay que revisar el esquema de la herramienta destino antes de
comprometer el trabajo.

---

## 6. Datos sensibles en las exportaciones

Antes de entregar cualquier exportación a un tercero:

- [ ] ¿El archivo contiene prompts y respuestas con datos personales del
      usuario final?
- [ ] ¿Se revisó el contenido, o se exportó a ciegas con filtros amplios?
- [ ] ¿Dónde se guarda el archivo después?
- [ ] ¿Se le pidió consentimiento al usuario final sobre el tratamiento de sus
      datos?

Este no es un detalle de formality. Las trazas guardan **literalmente** lo que el
usuario escribió.

---

## 7. Resumen

| Lo que quiere el cliente | Lo que existe |
| --- | --- |
| "Sacame los costos de este mes" | Exportar CSV desde la interfaz, o API de métricas |
| "Quiero tener los datos en una hoja" | Exportar CSV o JSON |
| "Quiero analizar el comportamiento de los usuarios" | Exportar JSON, o consultar por la API |
| "Quiero que los costos lleguen a Odoo solos" | **No existe.** Es un proyecto aparte |
| "Quiero mudar esta instalación a otro servidor" | Respaldo y restauración, incluidos en el kit |
| "Quiero salir de mi servidor y usar Langfuse Cloud" | **No verificado.** Confirmar antes de prometer |

---

## 8. Fuentes

- Exportación desde la interfaz: <https://langfuse.com/docs/api-and-data-platform/features/export-from-ui>
- Exportación programada a almacenamiento de objetos (de pago): <https://langfuse.com/docs/api-and-data-platform/features/export-to-blob-storage>
- API pública: <https://langfuse.com/docs/api-and-data-platform/features/public-api>
- Referencia de la API: <https://api.reference.langfuse.com>