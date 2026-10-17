# 06 — Actualizaciones y reversión

Langfuse publica versiones con mucha frecuencia y **la topología y las variables
de entorno cambian entre versiones mayores**. Actualizar sin leer los cambios es
la forma más rápida de romper una instancia en producción.

---

## 1. La regla de oro

> **No actualices Langfuse leyendo el número de versión nuevo y tirando
> `docker compose pull`.**

El `compose.yaml` de este kit está anclado a la topología de **v4.63.0**. Cuando
el orquestador del kit cambia, el `docker-compose.yml` de ese tag también cambia:
pueden aparecer servicios nuevos, renombrarse variables o exigir una versión
mayor de ClickHouse.

El procedimiento correcto es **leer el compose del tag nuevo** y actualizar el
propio.

---

## 2. Qué comprobar antes de actualizar

1. **Notas de la release**:
   <https://github.com/langfuse/langfuse/releases>

2. **`docker-compose.yml` del tag nuevo**, que es la fuente de la verdad:
   <https://raw.githubusercontent.com/langfuse/langfuse/vX.Y.Z/docker-compose.yml>

3. **Guía de actualización oficial**:
   <https://langfuse.com/self-hosting/upgrade/upgrade-guides>

4. **Matriz de compatibilidad**, para confirmar que los SDK que usa el cliente
   siguen soportados por la versión del servidor:
   <https://langfuse.com/self-hosting/upgrade/versioning>

Lo que hay que mirar en el compose del tag nuevo:

| Qué buscar | Por qué importa |
| --- | --- |
| Servicios nuevos | Puede aparecer un componente que falte en el despliegue |
| Servicios renombrados | Los volúmenes y los nombres cambian |
| Versiones de ClickHouse y PostgreSQL | Una versión mayor puede **exigir** migraciones |
| Variables nuevas | Puede haber alguna obligatoria sin valor por defecto |
| Cambios en los volúmenes | Si cambia una ruta, el respaldo viejo no se restaura igual |

---

## 3. Procedimiento de actualización

```bash
cd /opt/hefesto/langfuse

# 1. RESPALDAR PRIMERO. Sin excusas.
./scripts/backup-langfuse.sh --dir /mnt/disco-externo/respaldos
ls -lt /mnt/disco-externo/respaldos | head -3
```

Confirma que el respaldo terminó bien: debe existir `MANIFESTO.estado` con
`estado: completo`.

```bash
# 2. Leer el compose del tag nuevo y comparar
curl -sL https://raw.githubusercontent.com/langfuse/langfuse/vX.Y.Z/docker-compose.yml -o /tmp/compose-nuevo.yml
diff compose.yaml /tmp/compose-nuevo.yml
```

```bash
# 3. Actualizar los digests en compose.yaml
#    Resolver los nuevos digests de langfuse/langfuse y langfuse/langfuse-worker.
#    Ver VERSION.md, seccion 2, para el metodo de resolucion.

# 4. Levantar
docker compose pull
docker compose up -d
```

```bash
# 5. Observar. Aqui es donde se ven los problemas.
docker compose logs -f langfuse-web
```

Espera a "Ready". Puede tardar **2 a 3 minutos** por las migraciones.

```bash
# 6. Comprobar
curl -s https://observabilidad.ejemplo.cl/api/public/health
curl -s https://observabilidad.ejemplo.cl/api/public/ready
```

Después, verifica en la interfaz que: las trazas antiguas siguen ahí, los
proyectos existen y **las claves de API siguen funcionando**. Lo último es
crítico: si el cliente navega y ve trazas, no significa que su instrumentación
siga escribiendo.

---

## 4. Volver atrás (reversión)

La reversión **solo es segura si existe un respaldo previo a la actualización**.

```bash
# 1. Dejar todo detenido
docker compose down

# 2. Restaurar el estado anterior
./scripts/restore-langfuse.sh /mnt/disco-externo/respaldos/langfuse-AAAA-MM-DD-HHMMSS
```

El script deja los servicios detenidos a propósito. Cuando alguien revisó, se
levantan:

```bash
# 3. Volver a la imagen anterior, fijando el compose del tag viejo
docker compose up -d
```

### El problema de las migraciones

**VERIFICADO, y es el riesgo principal de esta sección:** las migraciones de
esquema que Langfuse ejecuta al arrancar **no siempre son reversibles**.

En concreto, las migraciones de **ClickHouse modifican el esquema de las tablas de
eventos**. Langfuse documenta que estas migraciones no se pueden deshacer
automáticamente. Langfuse v4 incluye migraciones de ClickHouse dentro del
proceso de arranque del servicio web.

Qué significa en la práctica:

| Estrategia | Veredicto |
| --- | --- |
| Bajar la versión de la imagen sin restaurar la base | **NO.** La base queda con el esquema nuevo y el software viejo espera el anterior |
| Restaurar el respaldo previo y bajar la imagen | Correcto, si el respaldo es de **antes** de actualizar |
| Restaurar solo PostgreSQL | No alcanza: el esquema de eventos está en ClickHouse |

Por eso el orden correcto es: **respaldar, actualizar, verificar**. Y si hay que
volver atrás, se restaura el respaldo completo hecho antes de subir.

> **Consecuencia para la planificación:** Hefesto debe avisar al cliente que
> existe una ventana sin vuelta atrás durante una actualización mayor. Si el
> cliente no puede aceptarla, la actualización se planifica fuera de horario
> comercial y con respaldo verificado.

---

## 5. Actualizar el resto de los componentes

Los otros cuatro servicios también se pueden actualizar por separado:

| Servicio | Estrategia |
| --- | --- |
| PostgreSQL | Actualizaciones menores directas. Las mayores requieren `pg_upgrade` y una ventana de mantenimiento |
| ClickHouse | Actualizaciones directas dentro de la misma versión mayor |
| Redis | Actualizaciones directas |
| MinIO | **Con cuidado.** Su licencia cambió en versiones recientes y su formato de datos cambió antes. Revisa las notas de la versión **antes** de actualizar |

El `compose.yaml` fija los cuatro por digest, así que **no se actualizan solos**.
Cada actualización es una decisión consciente con su propio digest.

---

## 6. Lista de verificación antes de actualizar en producción

- [ ] Respaldo terminado con `estado: completo` verificado.
- [ ] Respaldo **probado**: restaurado en otro servidor o máquina virtual.
- [ ] Notas de la release leídas, no solo el número de versión.
- [ ] `compose.yaml` del tag nuevo leído y comparado.
- [ ] Digests nuevos resueltos y anotados en `VERSION.md`.
- [ ] Ventana de mantenimiento acordada con el cliente.
- [ ] `SALT`, `ENCRYPTION_KEY` y `NEXTAUTH_SECRET` guardados en un lugar seguro.
- [ ] Verificación posterior planificada: salud, trazas antiguas, proyectos y
      **claves de API**.

---

## 7. Fuentes

- Releases: <https://github.com/langfuse/langfuse/releases>
- Guías de actualización: <https://langfuse.com/self-hosting/upgrade/upgrade-guides>
- Versionado y compatibilidad: <https://langfuse.com/self-hosting/upgrade/versioning>
- Compose del tag v4.63.0: <https://github.com/langfuse/langfuse/blob/v4.63.0/docker-compose.yml>