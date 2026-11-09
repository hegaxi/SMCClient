# Arquitectura de SMCClient

Aplicación para consultar proyectos **Scrum** (Jira Software) y de **mesa de ayuda** (Jira Service Management):
tickets, historias, tiempo invertido, SLA y avance de sprints.
Pila: SQL Server + API en C# con **un solo controlador** que lee los metadatos de los procedimientos
del esquema `api` y los ejecuta + React.

> Objetivo principal de este diseño: **que la aplicación siga funcionando cuando algo cambia en Jira**
> (campos nuevos, eliminados o renombrados, SLA nuevos, proyectos nuevos, cambios en la API de Atlassian)
> y que pueda crecer en volumen y en número de instancias de Jira sin rediseñarse.

---

## 1. Lo que se encontró en el Jira real (smco.atlassian.net)

Se revisaron proyectos y issues reales (solo lectura) para basar el diseño en datos y no en supuestos:

| Hallazgo | Consecuencia en el diseño |
|---|---|
| 21 proyectos: 12 `software` (Scrum), 8 `service_desk` (mesa de ayuda), 1 `business`. Tres son de pruebas (`TS25`, `TSM26`, `TSSM26`). | En Jira ambos son *issues*: un solo modelo `ops.Issue`, distinguido por `TipoProyecto`. Los proyectos de prueba se excluyen en `cfg.ProyectoExcluido` (ver §5.4). |
| Los SLA son campos personalizados (`customfield_10055` *Time to resolution*, `customfield_10056` *Time to first response*) con `slaDisplayFormat: NEW_SLA_FORMAT`: la búsqueda **no trae el ciclo en curso**. | Los SLA se leen de `/rest/servicedeskapi/request/{id}/sla`, que sí trae ciclo en curso y ciclos completados. Un SLA nuevo aparece solo (`SlaId` + `Nombre`). |
| La búsqueda trae solo **20 worklogs por issue** (`SMC26-18` tiene 96). | Los worklogs se sincronizan aparte con `/worklog/updated` + `/worklog/list`, y los borrados con `/worklog/deleted`. |
| Los worklogs los registra **Automation for Jira** (`accountType: app`): exactamente 1 día por cada día hábil que el issue sigue abierto, sin comentario (visto en mesa de ayuda y en Scrum). | No miden esfuerzo sino días abiertos. Se separan como `automatico` y se atribuyen al responsable del issue ese día (ver §5.6). |
| Los informantes de la mesa de ayuda son clientes del portal (`accountId` `qm:…`, `accountType: customer`) y Jira devuelve su correo. | `ops.Usuario` guarda nombre y tipo de cuenta, **no el correo** (dato personal que no se necesita). |
| Fechas con zona sin dos puntos: `2026-07-08T09:30:36.291-0600`. | Función `sync.fn_FechaJira`; todo se guarda como `datetimeoffset`. |
| Sprint en `customfield_10020` (`gh-sprint`), tipo de solicitud en `customfield_10010` (`vp-origin`). No se encontró campo de *story points* con valor en las muestras. | Los campos se encuentran por **reglas** (tipo custom o nombre), no por ID fijo. Si *story points* no existe, el rol queda sin campo y se avisa; no rompe nada. |

---

## 2. Principios

1. **Capa anticorrupción.** El vocabulario de Jira (customfield_XXXXX, ADF, formatos de fecha, endpoints) no pasa de la capa `raw`/`sync`. Lo que la API y React consumen es un modelo propio y estable (`ops`, `rpt`, `api`).
2. **Primero guardar, después interpretar (ELT con repetición).** El worker solo trae JSON y lo guarda en `raw.Documento`. La interpretación ocurre en SQL. Si cambia una regla, se **reprocesa desde `raw`** sin volver a llamar a Jira.
3. **Configuración en datos, no en código.** Endpoints, frecuencias, orden, procedimientos de integración y la relación *rol → campo de Jira* están en tablas `cfg`. Un cambio en Jira se resuelve con un `UPDATE`, no con un despliegue.
4. **Contratos estables hacia afuera.** Los procedimientos `api.*` tienen columnas fijas. Lo variable (campos personalizados) se entrega en formato largo (`CampoId, Campo, Valor`) que la interfaz convierte en columnas.
5. **Falla suave.** Un documento malo no detiene la sincronización (cuarentena); un rol sin campo deja la columna vacía y avisa; una respuesta incompleta de Jira no borra datos.
6. **Idempotencia.** Repetir una página, una corrida o un despliegue produce el mismo resultado (`MERGE` por llaves naturales, hash del documento, scripts repetibles).
7. **Observabilidad.** Toda corrida queda en `sync.Ejecucion`; todo cambio de Jira y todo problema queda en `sync.Evento`, visible para el administrador en la aplicación.

---

## 3. Capas

```
 Jira Cloud ──HTTP──► Worker C# (BackgroundService)             SQL Server
                       │ pagina, reintenta (429/5xx),           ┌──────────────────────────────────────┐
                       │ respeta Retry-After                    │ cfg   configuración editable          │
                       │                                        │ meta  catálogo de campos de Jira       │
                       └── TVP (lotes JSON) ─────────────────►  │ raw   JSON tal como llegó (repetible)  │
                                                                │ sync  ejecuciones, marcas, candados,   │
                                                                │       avisos, procedimientos Procesar_*│
                                                                │ ops   modelo canónico                  │
                                                                │ rpt   vistas de lectura                │
 React ◄── JSON ── ProcedimientosController ◄── EXEC ─────────  │ api   ÚNICOS procedimientos públicos   │
           (formularios generados por metadatos)                └──────────────────────────────────────┘
```

| Esquema | Quién escribe | Quién lee |
|---|---|---|
| `cfg` | Administrador (y `sync.Fuente_Registrar`) | Worker, `sync.*` |
| `meta`, `raw` | `sync.*` | `sync.*`, vistas |
| `sync` (tablas) | Worker vía procedimientos `sync.*` | `api.Sync_Estado`, `api.Avisos_Listar` |
| `ops` | Solo los procedimientos `sync.Procesar_*` | `rpt.*` |
| `api` | — | Controlador (rol `smc_api`, solo `EXECUTE`) |

---

## 4. Cómo resiste cambios en Jira

| Cambio en Jira | Qué pasa | Qué ve el administrador |
|---|---|---|
| **Se crea un campo personalizado** | Entra al catálogo (`meta.CampoJira`); sus valores se guardan solos en `ops.IssueCampoValor` (incluso antes de que llegue el catálogo, si es `customfield_*`). Se programa un **backfill** (`JQL cf[id] is not EMPTY`) porque la sincronización incremental no ve issues viejos que ya tenían valor. | Aviso `campo.alta` |
| **Se renombra un campo** | El ID no cambia: solo se actualiza el nombre. Reportes y detalle muestran el nombre nuevo. | Bitácora `meta.CampoJiraCambio` |
| **Se elimina un campo** | Se marca inactivo (`FechaBaja`). Los valores históricos se conservan. Si tenía un rol, el rol se vuelve a resolver. | Aviso `campo.baja` (incluye el rol afectado) |
| **Se recrea un campo con otro ID** (p. ej. story points) | La regla del rol (tipo custom o nombre) encuentra el nuevo; el mapeo cambia y los issues se **reprocesan desde `raw`**. | Aviso `rol.cambio` |
| **Dos campos cumplen la regla** | Se elige el de ID más bajo y se avisa; el administrador lo fija con `api.Mapeo_Establecer` (mapeo manual, nunca se sobrescribe). | Aviso `rol.ambiguo` |
| **Un rol obligatorio se queda sin campo** | La columna queda en `NULL`; la sincronización sigue. | Aviso `rol.sin_campo` |
| **Cambia el tipo de un campo** | Los valores nuevos se guardan según el tipo del JSON; lo que no se reconoce va a `ValorJson`. | Aviso `campo.cambio_tipo` |
| **Se crea o elimina un SLA en JSM** | Los SLA son filas (`SlaId`, `Nombre`, `Ciclo`), no columnas: aparecen o dejan de llegar solos. | Reportes de SLA lo incluyen |
| **Se renombra un estado o se crea un flujo nuevo** | Los reportes usan la **categoría** del estado (`new` / `indeterminate` / `done`), que es estable. | — |
| **Se mueve un issue de proyecto** (cambia su clave) | La llave es el `id` del issue, que no cambia; la clave se actualiza. | — |
| **Se crea un proyecto** | Llega en el catálogo y sus issues en la siguiente corrida (si entra en el `jqlBase`). | — |
| **Se borra un issue** | La conciliación diaria (`sync.Issue_ConciliarIds`) lo marca `Eliminado = 1`. | — |
| **Le quitan permisos al usuario técnico / Jira responde incompleto** | Si llega menos del `UmbralBajaCatalogoPct` (50 %) de lo que había, **no se da de baja nada**. | Aviso `*.catalogo_incompleto` |
| **Atlassian cambia o retira un endpoint** (como `/search` → `/search/jql` en 2025) | El endpoint está en `cfg.EntidadSync`; el worker encapsula cada endpoint en un adaptador. El modelo `ops` y la API no cambian. | — |
| **Jira devuelve un documento con forma inesperada** | Ese documento se reintenta solo, queda en cuarentena tras 3 fallos y el resto sigue. | Aviso `documento.error` y contador en `api.Sync_Estado` |
| **Límite de peticiones (429)** | El worker espera lo que indica `Retry-After` y continúa desde la última página guardada; la marca de agua solo avanza al terminar bien. | — |

---

## 5. La tarea de sincronización

### 5.1 Una corrida

```
para cada fuente activa (cfg.Fuente):
  para cada entidad activa en orden (cfg.EntidadSync.Orden):    campo → estado → proyecto → issue → changelog → worklog → worklog_eliminado → sla
     si no le toca por frecuencia y no hay solicitud: continuar
     sync.Ejecucion_Iniciar      → toma el candado de la fuente (lease); otro worker recibe el error 50010
     sync.MarcaAgua_Obtener      → "desde" = marca − 5 min (o carga inicial de 730 días)
     por cada página de Jira:
        sync.Documento_Cargar    → MERGE en raw.Documento; los documentos iguales (mismo hash) no se reprocesan
     sync.Procesar_Pendientes    → integra raw → ops por lotes y llama al cierre del catálogo (bajas, roles)
     sync.Ejecucion_Finalizar    → avanza la marca de agua solo si terminó bien (nunca la retrocede)
  sync.Candado_Liberar
atender sync.Solicitud pendientes (botón "Sincronizar ahora", backfill de campos nuevos, conciliación)
```

Las entidades `changelog` y `sla` son **dependientes**: se piden solo para los issues que cambiaron en la corrida
(y `sla` solo para proyectos `service_desk`).

### 5.2 "Sincronizar antes de hacer nada"

- Al arrancar la API, el `BackgroundService` hace la primera corrida y después revisa cada minuto qué entidades vencieron.
- El controlador ejecuta `api.Sync_Estado` antes de cualquier procedimiento. Si `DatosVigentes = 0` responde **503 `sync.pendiente`**,
  salvo para los procedimientos marcados con la propiedad extendida `smc:exentoSync = 1` (estado, avisos, catálogo).
- **`DatosVigentes` = la fuente ya completó su primera carga** (todas sus entidades no dependientes terminaron bien al menos una vez).
  Después, si Jira o el worker fallan, la aplicación **no se bloquea**: sigue respondiendo con lo que ya tiene y `DatosAtrasados = 1`
  hace que la interfaz muestre un aviso con el atraso. Un tipo de dato está atrasado cuando lleva sin sincronizarse más que **su
  frecuencia más el margen** `cfg.Fuente.MaxAntiguedadMin` (30 min por omisión): un catálogo que se pide cada hora no se marca
  atrasado a los 31 minutos.
- **Configuración por el administrador**: *Configuración de la sincronización* muestra cada tipo de dato con su frecuencia;
  *Cambiar frecuencia de sincronización* (`api.Sync_Frecuencia_Guardar`, 1 a 10 080 min) y *Cambiar margen de datos atrasados*
  (`api.Sync_Antiguedad_Guardar`). Queda en la auditoría y el worker lo toma en su siguiente ciclo (también historial, SLA y
  comentarios respetan su frecuencia).
  Antes cualquier atraso de 30 min dejaba sin servicio a todos (hallazgo del diagnóstico de arquitectura).
- React consulta `api.Sync_Estado` cada pocos segundos y muestra la pantalla de sincronización hasta que los datos estén vigentes.

### 5.3 El worker (C#)

`src/SMCClient.Sync` (biblioteca) + `src/SMCClient.Worker` (servicio de Windows). La biblioteca se puede hospedar
también dentro de la API con `services.AddSmcSync(configuracion)`.

| Pieza | Responsabilidad |
|---|---|
| `Sincronizador` | Recorre fuentes y entidades en el orden de la base; decide qué venció; atiende la cola de solicitudes; conciliación diaria. |
| `IExtractor` (uno por entidad) | Sabe hablar con **un** endpoint de Jira (paginación, formato) y entrega JSON crudo. Si Atlassian cambia un endpoint, se cambia solo su extractor. |
| `JiraCliente` | HTTP con autenticación (Cloud: correo + API token; Data Center: token personal) y resiliencia estándar: 6 reintentos ante 429/5xx/timeout respetando `Retry-After`, circuit breaker. |
| `SyncRepositorio` | Llama a los procedimientos `sync.*` (lotes JSON por TVP). No contiene SQL de negocio. |
| `SyncWorker` | `BackgroundService`: ciclo al arrancar y cada `IntervaloRevisionSegundos`. |

Detalles que cuidan la operación:

- **Zona horaria del JQL.** Jira interpreta las fechas del JQL en la zona del usuario técnico; el worker la consulta (`/myself`) y convierte la marca de agua.
- **Reintentos con espera.** Si una entidad falla, no se reintenta en cada ciclo sino tras `MinutosReintentoTrasError`; los datos dejan de estar vigentes y el aviso queda en `sync.Ejecucion`.
- **Paro ordenado.** Al detener el servicio se cierra la ejecución en curso y se libera el candado. Si el proceso muere, la siguiente ejecución que tome el candado cierra la abandonada.
- **Cola por fuente.** Cada worker solo toma solicitudes de las fuentes que tiene configuradas, así varias instancias no se bloquean entre sí.
- **Historial y SLA pendientes en la base (`sync.IssuePendiente`).** `sync.Procesar_Issues` encola el historial (y el SLA, en mesa de
  ayuda) de cada issue nuevo o cuya fecha de actualización cambió; un reproceso o backfill sin cambios no encola nada. El worker toma
  los pendientes (`sync.IssuePendiente_Tomar`) y los borra solo cuando ya los guardó (`sync.IssuePendiente_Completar`): si Jira falla
  o el worker se cae, se retoman en la siguiente corrida. Lo que falla 5 veces se reintenta una vez al día. La migración `0003` encoló
  los issues que nunca recibieron su historial. `api.Sync_Estado` muestra cuántos quedan (`IssuesPendientes`).
- **Carga inicial completa y padres faltantes.** `DiasCargaInicial = 0` (por omisión) trae todo, sin filtro de fecha. Además, después
  de cada corrida de issues, `sync.Padres_Pendientes` entrega las claves de padres o épicas que los issues mencionan y no están en la
  base (por ejemplo, de una carga inicial anterior limitada por fecha), y el worker los trae por clave (`/rest/api/3/issue/bulkfetch`,
  modo `padres`, que no mueve la marca de agua). Hasta 3 rondas por corrida, porque un padre traído puede tener su propio padre.

### 5.4 Proyectos excluidos

`cfg.ProyectoExcluido` (alta y baja con `sync.Proyecto_Excluir`). Un proyecto excluido:

- no se pide a Jira (el worker agrega `project not in (...)` al JQL),
- si llega de todos modos, la base lo da por procesado sin integrarlo y no se piden su changelog, worklogs ni SLA,
- se oculta en `rpt.*` y en `api.*` aunque ya tuviera datos.

Al volver a incluirlo se programa un backfill del proyecto completo (issues, historial, worklogs y SLA).
En smco están excluidos `TS25`, `TSM26` y `TSSM26` (`db/instancias/smco.sql`).

### 5.5 El controlador único (`src/SMCClient.Api`)

`ProcedimientosController` es el único controlador. Flujo de un `POST /api/procedimientos/{nombre}`:

```
1. Catálogo (en memoria)      ¿existe api.{nombre}?                         no → 404
2. Autorización               seg.Permisos_Usuario (roles en SQL Server)     sin sesión → 401, sin permiso → 403
3. Compuerta de sincronización api.Sync_Estado (caché de 5 s)               pendiente → 503 + Retry-After
                              (se salta si smc:exentoSync = 1)
4. Validación                 cada valor JSON al tipo exacto del parámetro   error → 400 con detalle por parámetro
                              obligatorios, desconocidos, longitud, rango
5. Ejecución                  CommandType.StoredProcedure + SqlParameter     THROW 5NNNN → 4xx con su mensaje
6. Respuesta                  todos los conjuntos de resultados + salidas    tope de Api:MaxFilas por conjunto
```

- **Metadatos.** `sys.procedures`, `sys.parameters`, `sys.dm_exec_describe_first_result_set_for_object` y las propiedades extendidas. SQL Server no registra qué parámetros de un procedimiento T-SQL tienen valor por omisión, así que se lee del encabezado del procedimiento. Se recargan solos cuando cambia algo en la base (una firma de fechas de modificación y propiedades), así un procedimiento nuevo aparece sin reiniciar.
- **Nada de SQL dinámico.** El nombre que se ejecuta sale del catálogo, nunca del texto del cliente; los valores viajan como parámetros tipados.
- **Parámetros de contexto.** Los listados en `Api:ParametrosDeUsuario` (hoy `@SolicitadoPor`) los llena el servidor con el usuario autenticado; no se exponen ni se aceptan del cliente.
- **Permisos mínimos.** La cuenta de la API solo tiene el rol `smc_api` (`EXECUTE` y `VIEW DEFINITION` sobre `api`); las pruebas corren con un login así.
- **Autenticación y autorización.** Usuarios y contraseñas en SQL Server con cookie de sesión (ver §8); los permisos los decide `seg.Permisos_Usuario` en cada petición (caché de 30 s que se descarta después de cualquier acción). Modo `Desarrollo` sin inicio de sesión, que la API rechaza fuera del ambiente Development.
- **Worker opcional dentro de la API** con `Api:HospedarWorker = true` (por omisión corre como servicio aparte).


### 5.6 Atribución de horas (worklogs)

En Jira el autor de los worklogs automáticos es la propia automatización y, en una regla programada, eso no se
puede cambiar. `rpt.vWorklog` agrega, sin perder el autor original:

| Columna | Valor |
|---|---|
| `Origen` | `manual` (lo registró una persona) o `automatico` (lo registró una app) |
| `AtribuidoA` | Manual: el autor. Automático: el responsable del issue **el día del worklog**, reconstruido del historial del campo assignee; si nunca cambió, el responsable actual; si no tenía, `(Sin responsable)` |
| `MetodoAtribucion` | `autor`, `historial` o `responsable_actual` (para auditar de dónde salió) |

Se calcula al consultar, así que si el historial llega después la atribución se corrige sola.
`api.Horas_PorPersona` entrega **HorasRegistradas** (esfuerzo real), **HorasAutomaticas** (días abiertos) y el total,
y permite filtrar por `@Origen`. Las automáticas suman 8 h por cada issue abierto, así que una persona con varios
issues abiertos puede tener más de 8 h automáticas en un día: no deben leerse como jornada trabajada.

### 5.6.1 Tiempo reportado en Scrum (subtareas y sprints)

En el Jira real (proyectos Scrum, últimos 60 días) las personas registran el tiempo **en las subtareas** (777 de 877 h
manuales) y Automation for Jira en las tareas o historias padre (928 h). El `timespent` de Jira de una historia solo
trae lo propio, así que no refleja el trabajo de sus subtareas. Por eso:

| Pieza | Qué hace |
|---|---|
| `ops.Issue.EsSubtarea` | Se lee de `issuetype.subtask` (migración `0001` la rellena desde `raw`, sin llamar a Jira) |
| `rpt.fn_HorasIssue` | Horas de un issue **más las de sus subtareas**, separadas en registradas y automáticas |
| Búsqueda avanzada | Campos *Horas registradas (con subtareas)*, *Horas automáticas (con subtareas)*, *Es subtarea*, *Registró tiempo (persona)* y *Fecha de registro de tiempo* (como `worklogAuthor` / `worklogDate` de JQL; cada criterio se evalúa por separado, igual que en Jira) |
| `api.Sprint_Avance` | Horas registradas y automáticas **dentro de las fechas del sprint** (de su inicio a su cierre; si sigue activo después de su fin, hasta hoy), en los issues del sprint y sus subtareas, cada worklog una vez: un issue que pasa de un sprint a otro no repite horas. Las subtareas no cuentan como issues |
| `api.Horas_PorSprint` | Horas por sprint y persona (registradas, automáticas atribuidas como en 5.6, total) |
| `api.Issue_Detalle` | Horas con subtareas y los worklogs de las subtareas (columna `Clave`) |

El tiempo registrado fuera de las fechas de cualquier sprint (antes de empezar o después de cerrar) no se asigna a
ningún sprint; sigue apareciendo en *Horas por persona* y en las horas del issue.

### 5.6.1.1 Comentarios

Entidad `comentario` (dependiente, con la cola `sync.IssuePendiente`): `GET /rest/api/2/issue/{id}/comment` (v2: el cuerpo llega
como texto, no como documento ADF), todas las páginas en un documento por issue. `ops.Comentario` guarda autor, texto, fechas y,
en mesa de ayuda, si es **público para el cliente o nota interna** (`jsdPublic`); los que ya no vienen se borraron en Jira. Se ven
en el detalle del issue y en la búsqueda (número de comentarios, último comentario, texto, quién comentó). La semilla `096`
agrega la entidad a las fuentes existentes y encola los comentarios de los issues que ya estaban.

### 5.6.2 Estimaciones (estimado vs. real)

Decisión del proyecto: **no se manejan tarifas ni costos**; **sí se capturarán estimaciones** en Jira (estimación original;
hoy casi no se usan: 4 de 40 issues en la muestra, y los story points no se usan). La sincronización ya trae la estimación
original y la restante; no hubo que cambiar el worker.

- **Siempre contra horas registradas por personas**: las automáticas (Automation for Jira) no son esfuerzo.
- **Con todo el árbol**: la estimación de una tarea incluye la de sus subtareas, y la de una épica la de sus tareas
  (como `aggregatetimeoriginalestimate` de Jira).
- `api.Estimacion_VsReal`: resumen (issues con y sin estimación, % capturado, horas estimadas y registradas, desviación,
  % consumido, excedidas) y detalle por issue con su situación (sin estimación, excedida, en curso, dentro de lo estimado);
  filtros por proyecto, épica, sprint, responsable y nivel.
- *Avance de épicas* agrega desviación, % consumido y tareas sin estimar; *Avance de sprints*, horas estimadas e issues sin
  estimar (un issue que pasa de sprint cuenta su estimación en cada uno: es lo comprometido en cada sprint).
- Búsqueda avanzada: horas estimadas (propias y con hijos), horas restantes, desviación y % consumido (p. ej. "tareas sin
  estimación" o "más del 100 % consumido").

### 5.6.3 Épicas

En el Jira real (197 épicas en los proyectos Scrum) las tareas cuelgan de la épica con el campo `parent` y las subtareas
de las tareas; las épicas no están en sprints y no tienen padre. El tiempo propio de una épica o de una tarea es solo una
parte del total: también registran Automation (en la épica y en las tareas) y las personas (en las subtareas).

| Pieza | Qué hace |
|---|---|
| `ops.Issue.NivelJerarquia` | `issuetype.hierarchyLevel` (1 épica, 0 estándar, -1 subtarea); si Jira no lo manda se deduce. Migración `0002` |
| `ops.Issue.PadreId` | Id de Jira del padre: **toda la jerarquía se une por id**, porque la clave cambia si el padre se mueve de proyecto (`PadreClave` queda solo para mostrar; la interfaz muestra la clave actual del padre). Migración `0004` |
| `rpt.fn_HorasIssue` | Horas registradas y automáticas, estimación y último registro de un issue **y todos sus descendientes** (hasta 5 niveles): una épica suma sus tareas y las subtareas de éstas |
| `rpt.fn_EpicaIssue` | Épica de un issue: él mismo, su padre o su abuelo (subtareas) |
| Búsqueda avanzada | Columna y criterio *Épica* (como `parent = X`, también para subtareas) y *Nivel* (épica / estándar / subtarea) |
| `api.Epicas_Avance` | Por épica: tareas, terminadas, % de avance, story points, horas estimadas, registradas y automáticas, último registro |
| `api.Horas_PorPersona @Epica` | Horas por persona de una épica (la épica, sus tareas y subtareas) |
| `api.Issue_Detalle` | Épica del issue y worklogs de todos sus descendientes |


### 5.7 La interfaz (`web/`)

React 19 + Vite, sin bibliotecas de componentes. Se publica dentro de la API (`wwwroot`), así que en IIS es una
sola aplicación con la misma autenticación de Windows.

- **Compuerta.** `useSincronizacion` consulta `api.Sync_Estado` cada 5 s mientras los datos no estén vigentes (cada minuto después). Cualquier 503 devuelve a la pantalla de sincronización.
- **Todo sale de los metadatos** de `GET /api/procedimientos`: menú, formularios, listas de opciones, títulos de resultados, qué es una acción. Las propiedades extendidas viven en `db/11_DatosSemilla/090_DescripcionesApi.sql`:

| Propiedad | Nivel | Uso en la interfaz |
|---|---|---|
| `smc:titulo` | procedimiento | Nombre en el menú |
| `MS_Description` | procedimiento / parámetro | Descripción y texto de ayuda |
| `smc:permiso` | procedimiento | Categoría (`lectura` / `admin` / `usuario` / `sesion`): grupo del menú y categoría que se puede conceder completa |
| `smc:opcion` | procedimiento | Opción de menú que agrupa los procedimientos de una pantalla (p. ej. `tableros`); sin ella cada procedimiento es su propia opción |
| `smc:exentoSync` | procedimiento | Responde aunque los datos no estén sincronizados |
| `smc:accion` | procedimiento | No corre sola al abrirla; pide confirmación |
| `smc:resultados` | procedimiento | Títulos de cada conjunto de resultados |
| `smc:opciones` | parámetro | Lista desplegable; también traduce esos valores en las tablas |
| `smc:oculto` | procedimiento | No aparece en el menú (lo usa una pantalla propia, p. ej. los campos de la búsqueda avanzada) |

- **Convenciones de presentación**: columnas `Clave` / `PadreClave` abren el detalle del issue; `TotalFilas` + `@Pagina` activan la paginación; un solo registro con más de 6 columnas se muestra como ficha en las consultas de detalle.


### 5.8 Filtros guardados y tableros (esquema `dash`)

| Tabla | Qué guarda |
|---|---|
| `dash.Filtro` | Una consulta del esquema `api` + sus valores en JSON. Los valores `{hoy}`, `{hoy-30}`, `{inicio_mes}`, `{inicio_mes_anterior}`, `{fin_mes_anterior}`, `{inicio_semana}`, `{inicio_anio}` son fechas relativas |
| `dash.Tablero` / `dash.TableroCompartido` | El tablero y con qué usuarios o roles se comparte |
| `dash.Widget` | Título, filtro, tipo (`indicador`, `barras`, `tabla`), configuración JSON, ancho y orden |
| `dash.Preferencia` | El tablero de inicio de cada usuario |

- **Lógica en SQL**: `dash.fn_FechaRelativa` / `dash.fn_ResolverParametros` convierten las fechas relativas; `api.Tablero_Obtener` entrega cada widget con su consulta y los parámetros ya resueltos y si quien lo ve puede ejecutarla (`seg.fn_ProcedimientosPermitidos`, la misma función que decide los permisos de la API).
- **Seguridad**: el widget se ejecuta por el controlador único con los permisos de quien ve el tablero; compartir un tablero no comparte permisos. Solo el propietario modifica filtros, tableros y widgets; un filtro usado por un widget no se borra; no se guardan filtros de acciones ni con los parámetros que pone el servidor.
- **Interfaz**: los widgets se arman con los metadatos de la consulta (columnas y tipos). El indicador "conteo" usa `TotalFilas` en consultas paginadas. Las barras son de una sola serie (un color validado para contraste en modo claro y oscuro, sin leyenda, valor en texto, tooltip al pasar o enfocar y vista de tabla).

### 5.9 Búsqueda avanzada (filtros desde cero, como el navegador de Jira)

Criterios sobre **cualquier** campo, columnas a elegir y ordenar, orden y paginación en el servidor.

| Pieza | Qué hace |
|---|---|
| `cfg.CampoConsulta` (semilla `11_DatosSemilla/040`) | Campos estándar: etiqueta, tipo (`texto`, `numero`, `fecha`, `lista`, `usuario`, `bit`), expresión SQL de un valor o de varios (sprints, etiquetas, componentes) y columnas predeterminadas |
| `rpt.fn_CamposBuscador()` | Une los estándar con los **personalizados de Jira** (`meta.CampoJira` activos que se guardan, clave `cf:<id>`), con su tipo deducido del esquema de Jira y los operadores de cada tipo. Un campo que Jira agrega aparece solo al sincronizar metadatos; uno que alimenta un campo estándar (sprint, story points, tipo de solicitud) no se repite |
| `api.Issues_Campos` / `api.Issues_Valores` | Campos y operadores; valores existentes de un campo con cuántos issues tiene cada uno (para los selectores) |
| `rpt.Buscador_Condiciones` | Valida los criterios y arma las condiciones; lo usan la búsqueda y el resumen, así filtran siempre igual |
| `api.Issues_Consultar` | `@Criterios` (arreglo JSON `{campo, operador, valor, hasta, valores}`), `@Columnas`, `@OrdenarPor`, `@Descendente`, `@Pagina`, `@TamanoPagina` (≤ 500) |
| `api.Issues_Resumir` | Mismos criterios; `@AgruparPor` (cualquier campo; fechas por mes; en campos de varios valores un issue cuenta en cada valor), `@Agregacion` (`conteo`, `suma`, `promedio`, `maximo`, `minimo`), `@Valor` (numérico), `@Top` (barras contando "Otros", que junta el resto contando cada issue una vez). **Sin tope de filas** |

Operadores: listas `en` / `no_en`; texto `contiene`, `no_contiene`, `igual`, `distinto`; números `igual`, `distinto`,
`mayor`, `mayor_igual`, `menor`, `menor_igual`, `entre`; fechas `desde`, `hasta`, `entre`, `igual` (fijas o relativas
`{hoy-30}`, `{inicio_mes}`…); sí/no `es`; todos `vacio` / `no_vacio`. Los criterios se combinan con Y. En campos de varios
valores `en` = alguno coincide y `no_en` = ninguno (incluye los que no tienen valor).

**Seguridad del SQL dinámico.** El SQL se arma solo con expresiones de la lista blanca (`rpt.fn_CamposBuscador`) y
operadores conocidos; los valores nunca se concatenan: la consulta los lee del propio JSON (`JSON_VALUE(@c, '$[k].valor')`,
`OPENJSON(@c, '$[k].valores')`) y se ejecuta con `sp_executesql`. Campos, operadores, columnas u orden desconocidos → 400
con un mensaje claro. `EXECUTE AS OWNER` porque el SQL dinámico no hereda el encadenamiento de propietarios (el rol
`smc_api` sigue sin leer tablas). Las pruebas (`db/tests/040`) incluyen intentos de inyección en campo, columnas, orden y valores.

**Interfaz.** `BuscadorIssues`: texto libre, chips para Proyecto / Tipo / Estado / Responsable y *+ Más criterios* (buscador
de campos agrupado en Jira / personalizados); cada criterio se edita según su tipo; *Columnas* (agregar, quitar, reordenar);
orden al hacer clic en el encabezado; CSV de hasta 500; todo vive en la dirección. *Guardar como filtro* lo deja disponible
para los widgets.

**Widgets sobre una búsqueda.** Las barras y los indicadores (suma, promedio, máximo, mínimo) no se calculan en el
navegador con las filas recibidas, sino en SQL Server con `api.Issues_Resumir` sobre **todos** los issues del filtro: no
quedan cortos aunque el filtro traiga miles. Se agrupa por cualquier campo (no solo por las columnas del filtro) y las
barras pueden contar issues. El indicador "conteo" usa `TotalFilas`. Solo las tablas muestran filas (las primeras N).
La prueba `db/tests/040` crea 1 200 issues y verifica que el resumen da 600 h donde una página de 500 daría 250 h.

### 5.10 Consultas personalizadas y clientes externos

- **Consulta personalizada** (`dash.Consulta`): una búsqueda avanzada con nombre que **publica quien tiene la opción *Publicar consulta personalizada*** (de fábrica, la administración) desde la
  búsqueda (*Publicar como consulta personalizada*) y comparte con usuarios o roles (`dash.ConsultaAcceso`, "ana, rol:Cliente").
  Quien tiene acceso la ve en el menú (*Consultas personalizadas*) y en la pantalla de inicio; solo elige orden y página: los
  criterios y columnas los define el administrador. Se validan con las mismas reglas de la búsqueda (lista blanca).
- **Clientes**: un rol **externo** (`seg.Rol.EsExterno`; se crea el rol *Cliente*). Un usuario externo:
  - solo puede tener opciones de la categoría `usuario` (consultas personalizadas y, si se las conceden, tableros y
    filtros), **aunque alguno de sus roles tenga más permisos** (`seg.fn_ProcedimientosPermitidos`): un error de
    configuración no le abre los reportes internos. El rol *Cliente* nace solo con *Consultas personalizadas*;
  - solo ve los tickets de **sus organizaciones de mesa de ayuda** (`seg.UsuarioOrganizacion`, *Organizaciones de un cliente*):
    `api.ConsultaPersonalizada_Ejecutar` agrega ese criterio en SQL Server. Sin organización asignada no ve tickets;
  - no ve el detalle del issue (comentarios internos, campos) ni el detalle interno de la sincronización.
- El campo *Organización (cliente)* sale del campo Organizations de JSM, resuelto por rol (`cfg.RolCampo` `organizacion`).
  *Organizaciones de mesa de ayuda* lista los nombres exactos y *Clientes (usuarios externos)* muestra cada cliente con sus
  organizaciones y consultas.

---

## 6. Escalabilidad

| Dimensión | Cómo escala |
|---|---|
| **Volumen de issues** | `raw.Documento` guarda solo la última versión de cada documento; el hash evita reprocesar lo que no cambió; la integración es por lotes (`TamanoLoteProceso`) y basada en conjuntos (sin cursores por fila). Índices filtrados para pendientes. |
| **Worklogs y valores de campos** | Son las tablas más grandes. Si superan decenas de millones de filas: índice columnstore no agrupado en `ops.Worklog` / `ops.IssueCampoValor` y particionado por fecha (se agrega como migración, sin cambiar la API). |
| **Varias instancias de Jira** | Todo está separado por `FuenteId`. Se agrega otra con `sync.Fuente_Registrar`. |
| **Varios workers** | Candado por fuente con lease que expira (si un worker muere, otro continúa). Las solicitudes se toman con `READPAST` (dos workers nunca toman la misma). Se puede tener un worker por fuente. |
| **Usuarios de la API** | La API no guarda estado: se pueden poner varias instancias detrás de IIS / balanceador. Las consultas pesadas pueden ir a una réplica de solo lectura. |
| **Nuevas consultas** | Un procedimiento nuevo en `api` aparece solo en la interfaz (metadatos). No se toca el controlador. |
| **Nuevas columnas canónicas** | Rol nuevo en `cfg.RolCampo` + columna en `ops.Issue` (migración) + una línea en `sync.Procesar_Issues`. |
| **Cálculos caros (horas, épica, atribución)** | Se calculan **al integrar**, no al consultar: `sync.Worklog_Atribuir` guarda en cada worklog su origen y a quién se atribuye; `sync.Resumen_Recalcular` guarda en `ops.IssueResumen` las horas propias y del árbol, la estimación, el último registro y la épica. `sync.Derivados_Actualizar` los mantiene al final de cada corrida, solo para los issues tocados (~1 s). Las consultas leen columnas. |

**Prueba de carga** (`db/tests/carga`, ver su README): 8 000 issues, 515 000 worklogs (450 000 de Automation), 300 épicas,
26 sprints. Antes de calcular al integrar, varias consultas tardaban de 6 a 31 s y *Avance de sprints* más de 10 min; ahora
las 18 consultas medidas tardan de 4 a 538 ms (presupuesto: 1,5 s interactivas, 3 s reportes). Un recálculo completo de la
atribución de 515 000 worklogs tarda ~31 s (solo tras una migración o un reproceso).

---

## 7. Orden de la base de datos

Ver [`db/README.md`](../db/README.md). Resumen: `00_Preparacion` → `01_Esquemas` → `02_Tipos` → `03_Tablas` →
`04_Migraciones` (una sola vez) → `05_LlavesForaneas` → `06_Indices` → `07_Funciones` → `08_Vistas` →
`09_Procedimientos` → `10_Seguridad` → `11_DatosSemilla`. `deploy.ps1` / `deploy.sh` siguen ese orden y
`--listar` lo imprime.

---

## 8. Seguridad

**Usuarios, contraseñas, roles y permisos viven en SQL Server** (esquema `seg`) y se administran desde la aplicación.
La lógica de negocio de seguridad está en procedimientos; .NET solo hace lo que no puede hacer la base:

| .NET (transporte y criptografía) | SQL Server (reglas) |
|---|---|
| Calcula el hash PBKDF2-SHA256 (600 000 iteraciones, sal aleatoria) y lo compara en tiempo constante; la contraseña en claro nunca llega a la base | Decide si el inicio de sesión procede: usuario activo, no bloqueado; cuenta intentos y bloquea (`seg.Login_Resultado`) |
| Emite la cookie de sesión (`HttpOnly`, `SameSite=Strict`, `Secure`) con el usuario y su sello | Valida el sello en cada petición: si cambió la contraseña o lo desactivaron, la sesión deja de valer (`seg.Permisos_Usuario`) |
| Exige el encabezado `X-SMC-Solicitud` en peticiones que modifican (CSRF) y limita intentos por IP | Longitud mínima, cambio obligatorio, quién puede restablecer a quién (`seg.Contrasena_Establecer`) |
| Pone `@UsuarioActual` / `@SolicitadoPor` con el usuario de la sesión (el cliente no puede enviarlos) | Qué procedimientos puede ejecutar cada usuario según sus roles; reglas de administración y auditoría (`api.Usuario_Guardar`, `api.Rol_Guardar`...) |

- **Roles y opciones del menú**: **toda opción del menú se concede por rol**; nada queda abierto a cualquier usuario salvo la categoría `sesion` (`api.Mi_Usuario` y `api.Sync_Resumen`, sin los que la aplicación no abre).
  - Un rol recibe en `seg.RolPermiso` opciones (`seg.fn_Opciones`: `tableros`, `tableros.editar`, `filtros`, `busqueda_avanzada`, `consultas_personalizadas`, `contrasena.restablecer` y un `api.X` por cada otro procedimiento) o categorías completas (`usuario`, `lectura`, `admin`), que incluyen lo que se agregue después.
  - `seg.fn_OpcionProcedimiento` da la categoría y la opción de cada procedimiento a partir de `smc:permiso` y `smc:opcion`, así que un procedimiento nuevo aparece solo en la matriz.
  - De fábrica: `Administrador` (`admin`, `lectura`, `usuario`), `Consulta` (`lectura`, `usuario`) y `Cliente` (`consultas_personalizadas`). La migración `0007` dio la categoría `usuario` a los roles que ya existían, para no quitarle nada a nadie.
  - Pantalla *Permisos por opción* (`api.Permisos_Matriz`, `api.Rol_Opcion_Establecer`): una casilla por opción y rol, con las reglas de `api.Rol_Guardar` y auditoría. Restablecer contraseña es la opción `contrasena.restablecer`, que revisa `seg.Contrasena_Establecer` (`seg.fn_TieneOpcion`); la sesión trae `puedeRestablecerContrasena` para mostrarla.
- **Primer administrador**: `dotnet SMCClient.Api.dll crear-administrador` con una conexión de administración; `seg.Instalacion_CrearAdministrador` no está concedido al rol `smc_api`, así que la aplicación web no puede crear administradores por esa vía.
- **Cuentas de SQL**: la API usa una cuenta con el rol `smc_api` (solo `EXECUTE` sobre `api` y sobre los cuatro procedimientos de sesión de `seg`); el worker, `smc_sync`.
- Token de Jira en un almacén de secretos o variables de entorno, nunca en `appsettings.json`; usuario técnico de Jira de solo lectura.

## 9. Decisiones pendientes

1. ~~Worklogs de Automation for Jira~~: resuelto (§5.6). Si en el futuro las personas registran horas a mano, aparecerán solas como `HorasRegistradas`.
2. **Story points.** No se encontró el campo con valor en las muestras. ¿Lo usan? ¿Con qué nombre?
3. ~~Proyectos de prueba~~: resuelto, se excluyen `TS25`, `TSM26` y `TSSM26`. Los temporales (`S22T`, `S2T`) siguen incluidos; se excluyen con `sync.Proyecto_Excluir` si se decide.
4. **Horario laboral para SLA propios.** JSM ya calcula los SLA con su calendario. Si se quieren métricas que JSM no tiene (p. ej. tiempo en cada estado en horario laboral), se agrega un calendario en `cfg`.
