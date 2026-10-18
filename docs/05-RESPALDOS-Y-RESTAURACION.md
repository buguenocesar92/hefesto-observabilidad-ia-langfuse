# 05 — Respaldos y restauración

Este es el documento más importante del kit. Langfuse v4 usa **dos almacenes de
datos distintos** más un almacén de objetos, y un respaldo incompleto no sirve
para nada.

Los scripts de este kit están en `scripts/backup-langfuse.sh` y
`scripts/restore-langfuse.sh`.

---

## 1. Qué es persistente

Los cinco volúmenes del `compose.yaml`. El nombre real lleva el prefijo del
proyecto (aquí `langfuse_`), por ejemplo `langfuse_langfuse_postgres_data`.

| Volumen | Qué guarda | ¿Irreemplazable? |
| --- | --- | --- |
| `langfuse_postgres_data` | **Estado de la aplicación**: usuarios, organizaciones, proyectos, membresías, **claves de API**, prompts, conjuntos de datos, configuraciones | **SÍ.** Es lo más crítico |
| `langfuse_clickhouse_data` | **Almacén de eventos**: trazas, observaciones, puntuaciones, uso y costos | **SÍ**, salvo que el cliente regenere las trazas reejecutando sus aplicaciones |
| `langfuse_minio_data` | **Almacén de objetos**: medios subidos (imágenes, archivos) e ingresos crudos de ingesta | **Parcialmente.** Los medios se pueden volver a subir; los ingresos crudos solo salen del respaldo |
| `langfuse_clickhouse_logs` | Logs del servidor ClickHouse | No. Es descartable |
| `langfuse_redis_data` | Cache y cola de trabajos | **No.** Es regenerable |

---

## 2. Por qué hay dos almacenes, y por qué importa

Este es el punto que define el diseño del respaldo.

- **PostgreSQL** guarda el estado: usuarios, organizaciones, proyectos,
  membresías, **claves de API**, prompts y conjuntos de datos.
- **ClickHouse** guarda los eventos: trazas, observaciones, puntuaciones y el
  desglose de costos.

La documentación oficial es explícita: **Langfuse no puede autoalojarse sin
ClickHouse.** No es un componente opcional ni un extra para escala.

Consecuencias directas, y hay que decírselas al cliente:

| Respaldo | Resultado |
| --- | --- |
| Solo PostgreSQL | **Se pierden todas las trazas.** Las claves de API y los proyectos sobreviven |
| Solo ClickHouse | **Se pierden los proyectos y las claves de API.** La instrumentación existente deja de funcionar |
| Los dos | La instancia se puede reconstruir |

---

## 3. Qué NO se respalda, y por qué

| Elemento | Por qué no |
| --- | --- |
| **Redis** (`langfuse_redis_data`) | Es cache y cola. Se reconstruye solo al arrancar. **Lo que se pierde:** los trabajos encolados en ese instante (exportaciones, evaluaciones) que no habían alcanzado a procesarse |
| **Logs de ClickHouse** (`langfuse_clickhouse_logs`) | Logs del motor. No contienen datos de negocio |
| **El `.env`** | **No va en el respaldo.** Contiene secretos. Véase la sección 8 |
| **Los archivos de Compose** | Se recuperan desde el repositorio del kit |
| **Los datos del cliente fuera de Langfuse** | Este kit no los toca |

---

## 4. Cómo obtener una copia coherente

La coherencia es el problema técnico real de este respaldo.

### PostgreSQL — se puede respaldar en marcha

`pg_dump` en formato custom (`-Fc`) es **consistente por transacción**: o sale
el estado completo, o nada. No hace falta detener la aplicación.

### ClickHouse y MinIO — hay que detener

Archivar el volumen de ClickHouse **con el servidor corriendo** produce una
copia inconsistente. La razón es que el motor escribe en muchos archivos a la
vez y un `tar` a mitad de escritura captura datos en estados incompatibles.

Por eso `backup-langfuse.sh` hace esto, en este orden:

1. `pg_dump` de PostgreSQL, con todo en marcha.
2. Detiene `langfuse-worker` y `langfuse-web` (los que escriben).
3. Detiene `clickhouse` y `minio`.
4. Archiva sus volúmenes, ahora consistentes.
5. Vuelve a levantar los servicios.
6. Calcula los SHA-256 y verifica.
7. Marca el respaldo como completo.

Detener los servicios implica que **Langfuse no acepta trazas durante el
respaldo**. En una instancia en producción, conviene programarlo en una
ventana de bajo uso. El detalle del trade-off está en la sección 9.

---

## 5. Cómo respaldar

```bash
cd /opt/hefesto/langfuse

# La primera vez
chmod +x scripts/*.sh

# Respaldar al directorio por defecto (./respaldos/)
./scripts/backup-langfuse.sh

# Respaldar a un disco externo
./scripts/backup-langfuse.sh --dir /mnt/disco-externo/respaldos
```

Resultado esperado:

```
respaldos/langfuse-20261017-031500/
├── postgres.dump          # estado de la aplicación
├── clickhouse.tar.gz      # trazas y observaciones
├── minio.tar.gz           # medios e ingresos crudos
├── MANIFESTO.sha256       # checksums de los tres artefactos
└── MANIFESTO.estado       # metadatos, con estado: completo
```

### Programación automática

```cron
0 3 * * * /opt/hefesto/langfuse/scripts/backup-langfuse.sh --dir /mnt/disco-externo/respaldos >> /var/log/respaldo-langfuse.log 2>&1
```

> **Ojo:** mientras el respaldo corre, Langfuse está detenido unos segundos o
> algunos minutos. Si el cliente tiene ingestión continua, conviene confirmar
> que esa ventana es aceptable.

### Rotación

Los respaldos consumen espacio y los antiguos no sirven para recuperar "el estado
de ayer". Una rotación sencilla:

```bash
find /mnt/disco-externo/respaldos -maxdepth 1 -type d -name 'langfuse-*' -mtime +30 -exec rm -rf {} +
```

> **Advertencia seria:** este `rm -rf` es irreversible. Ajusta el plazo a lo que
> el cliente pueda perder realmente y confirma que el destino es el correcto
> antes de programarlo en cron. Hefesto no lo ejecuta automáticamente.

---

## 6. Manifiesto y verificación

`backup-langfuse.sh` escribe `MANIFESTO.sha256`, que se puede verificar a mano
en cualquier momento:

```bash
cd respaldos/langfuse-20261017-031500
sha256sum -c MANIFESTO.sha256
```

Salida esperada:

```
postgres.dump: OK
clickhouse.tar.gz: OK
minio.tar.gz: OK
```

El script además valida que el dump de PostgreSQL sea realmente restaurable, con
`pg_restore --list`, antes de declarar el respaldo terminado.

### El respaldo se marca completo solo al final

`MANIFESTO.estado` empieza con `estado: en_progreso` y recién al final, cuando
todos los pasos salieron bien, pasa a `estado: completo`.

`restore-langfuse.sh` **se niega a restaurar** un respaldo que no tenga
`estado: completo`. Si un respaldo se cortó a mitad, no se usa a medias.

---

## 7. Cómo restaurar

### Antes de restaurar

- [ ] Toma un respaldo del estado **actual**, por si la restauración va mal.
- [ ] Verifica que tienes el `.env` correcto.
- [ ] Confirma que `SALT`, `ENCRYPTION_KEY` y `NEXTAUTH_SECRET` son los del
      respaldo. **Si no coinciden, las claves de API del respaldo no validarán.**

### Procedimiento

```bash
./scripts/restore-langfuse.sh respaldos/langfuse-20261017-031500
```

El script, en orden:

1. Verifica que el respaldo esté marcado como completo.
2. Verifica el **SHA-256 de todos los artefactos**. Si algo no calza, se detiene
   sin tocar nada.
3. **Revisa cada ruta dentro de los archivos tar** y rechaza las que sean
   absolutas o contengan `..`. Esto evita que un respaldo manipulado escriba
   fuera del volumen destino.
4. Se niega a continuar si el destino ya tiene datos, salvo que se pase
   `--force`.
5. Restaura PostgreSQL, ClickHouse y MinIO.
6. **Deja los servicios DETENIDOS.**

### Opciones

| Opción | Para qué |
| --- | --- |
| `--force` | Permite restaurar sobre un destino con datos. **Borra el contenido actual de los volúmenes** |
| `--solo-postgres` | Restaura solo el estado de la aplicación, sin tocar ClickHouse ni MinIO |

> `--solo-postgres` deja la instancia **incoherente**: el estado puede ser de
> una fecha y las trazas de otra. Úsalo solo para recuperar claves de API o
> usuarios, y avisa al cliente del resultado.

### Después de restaurar

```bash
docker compose up -d
docker compose logs -f langfuse-web
```

El primer arranque puede tardar **2 a 3 minutos** mientras corren las
migraciones.

### Garantías del script de restauración

| Garantía | Cómo se cumple |
| --- | --- |
| Nunca hace `DROP DATABASE` | No existe ese camino en el script. Con `--force` usa `pg_restore --clean`, que borra objetos individuales, no la base |
| No sobrescribe sin permiso | Sin `--force`, `pg_restore` falla si la base tiene datos, y el script se detiene |
| Verifica antes de actuar | SHA-256 y revisión de rutas, antes de extraer nada |
| Queda detenido | Los servicios se dejan apagados al final |

---

## 8. Secretos que hay que conservar aparte

Esto es lo que **no** está en el respaldo y **no** se puede recuperar del
respaldo:

| Secreto | Dónde está | Qué pasa si se pierde |
| --- | --- | --- |
| `SALT` | `.env` | Las claves de API dejan de validar |
| `ENCRYPTION_KEY` | `.env` | Ídem, y los secretos cifrados quedan ilegibles |
| `NEXTAUTH_SECRET` | `.env` | Se invalidan las sesiones activas |
| Contraseñas de PostgreSQL, ClickHouse, Redis y MinIO | `.env` | Hay que cambiarlas también **dentro** de cada servicio |
| La *secret key* del proyecto de Langfuse | Interfaz del proyecto | Hay que generar una nueva |

> **El punto que hay que comunicar al cliente.** Las claves de API de Langfuse
> **son credenciales**. Si se pierde este respaldo de PostgreSQL, o se cambian
> esos valores, las claves existentes dejan de validar y hay que rehacer la
> instrumentación de todas las aplicaciones del cliente. No es una molestia
> administrativa: es trabajo de implementación de nuevo.

Recomendación: guardar `.env` cifrado en el mismo gestor de secretos que el
resto de las claves del cliente, y **una copia offline** de los tres valores
críticos.

---

## 9. Límites y qué hacer ante un fallo parcial

| Situación | Qué hacer |
| --- | --- |
| El respaldo falló a mitad | **No sirve.** `MANIFESTO.estado` seguirá en `en_progreso`. Bórralo y vuelve a correr |
| Faltan tablas en Postgres tras restaurar | Se restauró sobre una base que ya tenía datos con otra estructura. Repite sobre una base limpia |
| El web no levanta tras restaurar | Revisa `docker compose logs langfuse-web`. Suele ser una migración pendiente |
| Las trazas aparecen pero sin costos | El respaldo de ClickHouse quedó desalineado con el estado. Revisa las fechas del respaldo |
| No se ven los medios | El volumen de MinIO no se restauró, o el endpoint no es alcanzable |

### Límites conocidos y honestos

- **Este esquema no respalda de forma consistente una instancia en producción
  en uso.** Detener los servicios para archivar ClickHouse genera una ventana
  sin servicio. Para un cliente con carga continua, la alternativa es la copia
  nativa de ClickHouse (`BACKUP`) hacia almacenamiento de objetos. Está
  documentada por upstream y **no está implementada** en este kit.
- **No hay copia incremental.** Cada respaldo es completo. Con volúmenes grandes
  esto se nota en disco y en tiempo.
- **No hay respaldo de los medios hacia almacenamiento externo.** MinIO está en el
  mismo servidor que Langfuse.
- **El script no sabe qué respaldar de forma selectiva.** Se respalda todo o nada.
- **Los scripts se validaron sintácticamente, no se ejecutaron.** No hay Docker
  en el entorno donde se preparó este kit. Ver `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 10. Fuentes

- Estrategia de respaldos de upstream: <https://langfuse.com/self-hosting/configuration/backups>
- Infraestructura de ClickHouse: <https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse>
- Infraestructura de PostgreSQL: <https://langfuse.com/self-hosting/deployment/infrastructure/postgres>
- Retención de datos: <https://langfuse.com/docs/administration/data-retention>