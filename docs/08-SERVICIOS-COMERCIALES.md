# 08 — Servicios comerciales

Este documento es el que Hefesto usa para decidir qué puede ofrecer y qué no.
Está deliberadamente escrito para que **no sobreprometa**.

---

## 1. A quién le sirve

### Cliente típico

- **Empresa que ya usa IA en producción** y necesita saber cuánto gasta, dónde se
  demora y qué prompts fallan.
- **Cliente con Dify de Hefesto** que quiere medir sus aplicaciones. Ver
  `ejemplos/02-DIFY-LANGFUSE-NATIVO.md`.
- **Equipo de desarrollo** que necesita depender de un servicio de
  observabilidad en la nube, por razones de cumplimiento o de costo.

### Cliente que NO le sirve

| Caso | Por qué no |
| --- | --- |
| Quiere una plataforma de IA | Langfuse **no** ejecuta ni entrena modelos. No es Dify |
| Quiere generar tráfico o respuestas a usuarios | Hay que mirar Dify o el kit de IA aplicada |
| Busca una nube administrada | Esto es autoalojado. El cliente opera su servidor |
| Busca soporte 24/7 | No está en el alcance de este kit |

---

## 2. Qué es Langfuse y qué no es

Esto hay que repetirlo en cada propuesta comercial, porque es el malentendido más
frecuente:

> **Langfuse NO es un producto de IA.** No ejecuta modelos, no entrena modelos,
> no genera respuestas a usuarios. Es una capa de **observabilidad**: registra
> lo que tu aplicación ya le pidió a un modelo y te dice cuánto costó, cuánto
> tardó y si salió bien.

La relación con Dify:

- **Dify construye** la aplicación (chatbots, RAG, agentes).
- **Langfuse la mide.**

Se pueden usar juntos o por separado, y Langfuse funciona con **cualquier**
proveedor de modelos: OpenAI, Anthropic, Google, modelos propios, gateways.

**No es un kit de IA local y no requiere GPU.** Langfuse observa modelos que ya
se están usando, en la nube o donde estén. No hay promesas de rendimiento de
modelos ni de hardware: Hefesto no vende ni construye modelos en este kit.

---

## 3. Qué puede vender Hefesto

| Servicio | Descripción |
| --- | --- |
| Despliegue en servidor del cliente | Instalación completa del kit |
| Configuración de proxy y TLS | Dominio, certificado, endurecimiento |
| Instrumentación de aplicaciones | Adaptar el SDK o la integración nativa de Dify |
| Puesta en marcha de respaldos | Configurar y verificar el ciclo de respaldo |
| Definición de modelos y costos | Ajustar precios cuando el proveedor los cambia |
| Tableros y alertas | Configurar las vistas que el cliente va a mirar |
| Capacitación al equipo | Cómo leer las trazas y actuar sobre ellas |

---

## 4. Los límites de la edición libre

Esta sección existe para **no prometer lo que no está**. Las restricciones
identificadas en la documentación oficial.

### 4.1 Lo que la edición libre autoalojada SÍ tiene

- **Usuarios ilimitados.** No hay límite de usuarios en autoalojado.
- **Sin límite de eventos ni de trazabilidad.**
- **Sin límite de retención.** Los datos se guardan **indefinidamente**.

> Esto es una diferencia importante frente a Langfuse Cloud, que sí tiene
> ventanas de acceso a datos y cuotas. En autoalojado, esas restricciones no
> aplican.

### 4.2 Lo que es de pago

| Función | Disponibilidad | Nota |
| --- | --- | --- |
| **Retención automática de datos** | **Enterprise** | En la edición libre **no hay borrado automático**. Ver el riesgo en 4.3 |
| **SSO empresarial** (Okta, Azure AD, Keycloak, etc.) | De pago | Funciona con cualquier proveedor OIDC |
| **Aplicación forzada de SSO** | De pago | Por dominio |
| **Aprovisionamiento SCIM** | De pago | Okta requiere una segunda aplicación |
| **Control de acceso detallado (RBAC granular)** | De pago | En la edición libre el acceso es por membresía |
| **Gestión de retención a nivel de organización** | De pago | |
| **Exportaciones programadas a almacenamiento de objetos** | De pago | Variables `LANGFUSE_S3_BATCH_EXPORT_*` |
| **Registro de auditoría** | De pago | |
| **Límites de tasa a medida, SLA** | De pago | |
| **Certificaciones SOC 2 / ISO 27001** | De pago | Solo en los planes de nube |

> La disponibilidad de **SSO en autoalojado** figura como "Disponible" en la
> tabla de planes de la documentación de nube. La distinción clara es esta: el
> núcleo MIT trae el acceso por correo y contraseña; el SSO empresarial, el SCIM,
> el RBAC granular y la retención son la capa de empresa.

### 4.3 El riesgo que hay que decir antes de firmar

**En la edición libre autoalojada, los datos no se borran solos.** La retención
automática es una función de pago.

Consecuencias concretas para el cliente:

1. **El disco se llena.** Las trazas, observaciones y puntuaciones se acumulan
   indefinidamente. ClickHouse es el volumen que crece.
2. **El costo de almacenamiento sube sin que nadie lo note**, porque no hay
   factura que lo delate.
3. **El cliente termina borrando datos a mano** desde la interfaz, lo cual es
   lento y poco confiable.

**Qué hacer:** con el cliente, **antes** de entregar, acordar una política de
conservación: cuántos meses de historial se guardan y quién revisa el crecimiento
del disco. Hefesto puede configurar la eliminación periódica en el servidor,
pero eso es operación, no producto.

### 4.4 Límites técnicos de este kit

| Límite | Detalle |
| --- | --- |
| Un cliente por instancia | Ver sección 5 |
| Respaldo con ventana de servicio | Detener los servicios para archivar ClickHouse |
| Sin copia incremental | Cada respaldo es completo |
| Sin alta disponibilidad | Un solo nodo. Si el servidor cae, no hay Langfuse |
| Sin probado en servidor | Estado real: `kit preparado` |

---

## 5. Multi-tenancy: lo que hay que decir

> **Una instancia de este kit es para un cliente. No hay aislamiento entre
> clientes.**

No es que Hefesto quiera acortarlo: **no existe**. Un despliegue de este kit es
una instancia dedicada. Si el cliente pide "mis tres marcas en la misma
instancia", hay que decirle que:

- todos los miembros de una organización ven los datos de los proyectos de esa
  organización;
- no hay RBAC granular en la edición libre;
- no hay aislamiento criptográfico entre proyectos.

La alternativa honesta es **una instancia por cliente**. Eso significa más
servidores, más respaldos y más mantenimiento. Es una decisión comercial que hay
que presentar con su costo.

---

## 6. Lo que NO se puede prometer

Estas son las frases que Hefesto **no debe** usar:

| No prometer | Por qué |
| --- | --- |
| "Se acabaron los problemas de costo" | Los costos se miden, no se eliminan. El modelo sigue cobrando lo que cobra |
| "Cero latencia adicional" | Hay tráfico de red adicional. Los SDK son asíncronos y la documentación dice que agregan poca latencia, pero no es cero |
| "No pierde datos" | Hay que probar el respaldo. Un respaldo no probado no es un respaldo |
| "Es gratis para siempre" | El núcleo es MIT y no hay que pagar a Langfuse, pero el servidor, el disco y el trabajo los paga el cliente |
| "Se integra con cualquier cosa" | Hay SDKs para Python y JS/TS, y OpenTelemetry para el resto. "Cualquiera" es demasiado |
| "Retiene los datos lo que el cliente quiera" | La retención automática es de pago |
| "Cumple con la normativa del cliente" | Sin certificaciones en la edición libre. La decisión de cumplimiento es del cliente |
| "Funciona con IA local" | Funciona **con** modelos locales, pero no los ejecuta ni los sirve. No requiere GPU, pero tampoco los provee |

---

## 7. Sobre Supabase

**Lo que se verificó:**

- Langfuse usa PostgreSQL de forma nativa y **declara compatibilidad con
  PostgreSQL 12 o superior**, con mínimo **15** y **16** recomendado para v4.
  Usa el esquema `public`.
- El `compose.yaml` oficial de v4.63.0 usa **PostgreSQL 17**.

**Lo que NO se verificó, y por eso no se promete:**

- **Langfuse necesita ClickHouse**, que es un motor analítico distinto. **Supabase
  es PostgreSQL.** No puede alojar ClickHouse.
- **MinIO**, el almacén de objetos, tampoco es PostgreSQL.

Conclusión, y es la que hay que comunicar:

> **Supabase puede cubrir solo una parte de esta arquitectura: el estado de la
> aplicación.** Los otros dos almacenes —ClickHouse (trazas) y el almacén de
> objetos (medios)— seguirían necesitando su propia infraestructura.
>
> **Hefesto no ofrece una variante sobre Supabase** porque no se verificó que
> funcione: la versión de PostgreSQL de un proyecto Supabase, las extensiones
> disponibles, el tipo de conexión y el rendimiento con la carga real de Langfuse
> **no se comprobaron**. Si un cliente lo exige, hay que revisarlo con pruebas
> reales antes de comprometerlo.

Si algún día se implementa, la regla sería la de siempre: **una base dedicada y
un usuario con permisos mínimos**, nunca el usuario administrador. Y el
navegador nunca se conecta a la base.

---

## 8. Posicionamiento honesto frente a las alternativas

| Si el cliente quiere… | Langfuse autoalojado |
| --- | --- |
| Cero costo de suscripción | **Sí**, el núcleo es MIT |
| Datos que no salen de su servidor | **Sí**, autoalojado |
| Retención automática sin trabajo | **No**, es de pago |
| SSO y control de acceso fino | **No**, es de pago |
| Cero mantenimiento | **No**, hay que operarlo |
| Certificaciones de cumplimiento | **No** |

El valor para el cliente no es "gratis": es **poder medir su aplicación sin
depender de un servicio de nube y sin enviarle los datos a un tercero**.

---

## 9. Fuentes

- Precios y límites por plan: <https://langfuse.com/pricing>
- Retención de datos: <https://langfuse.com/docs/administration/data-retention>
- Autenticación y SSO: <https://langfuse.com/docs/administration/authentication-and-sso>
- Roles y control de acceso: <https://langfuse.com/docs/administration/rbac>
- Infraestructura de PostgreSQL: <https://langfuse.com/self-hosting/deployment/infrastructure/postgres>