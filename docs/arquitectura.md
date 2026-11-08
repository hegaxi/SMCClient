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
2. Autorización               smc:permiso lectura/admin vs. grupos de AD     no → 403
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
- **Autenticación.** Windows (Negotiate / IIS) en intranet; grupos de AD para lectura y administración, leídos de la configuración en cada evaluación. Modo `Desarrollo` sin autenticación, que la API rechaza fuera del ambiente Development.
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


### 5.7 La interfaz (`web/`)

React 19 + Vite, sin bibliotecas de componentes. Se publica dentro de la API (`wwwroot`), así que en IIS es una
sola aplicación con la misma autenticación de Windows.

- **Compuerta.** `useSincronizacion` consulta `api.Sync_Estado` cada 5 s mientras los datos no estén vigentes (cada minuto después). Cualquier 503 devuelve a la pantalla de sincronización.
- **Todo sale de los metadatos** de `GET /api/procedimientos`: menú, formularios, listas de opciones, títulos de resultados, qué es una acción. Las propiedades extendidas viven en `db/11_DatosSemilla/090_DescripcionesApi.sql`:

| Propiedad | Nivel | Uso en la interfaz |
|---|---|---|
| `smc:titulo` | procedimiento | Nombre en el menú |
| `MS_Description` | procedimiento / parámetro | Descripción y texto de ayuda |
| `smc:permiso` | procedimiento | Grupo del menú (y autorización en la API) |
| `smc:exentoSync` | procedimiento | Responde aunque los datos no estén sincronizados |
| `smc:accion` | procedimiento | No corre sola al abrirla; pide confirmación |
| `smc:resultados` | procedimiento | Títulos de cada conjunto de resultados |
| `smc:opciones` | parámetro | Lista desplegable; también traduce esos valores en las tablas |

- **Convenciones de presentación**: columnas `Clave` / `PadreClave` abren el detalle del issue; `TotalFilas` + `@Pagina` activan la paginación; un solo registro con más de 6 columnas se muestra como ficha en las consultas de detalle.

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

---

## 7. Orden de la base de datos

Ver [`db/README.md`](../db/README.md). Resumen: `00_Preparacion` → `01_Esquemas` → `02_Tipos` → `03_Tablas` →
`04_Migraciones` (una sola vez) → `05_LlavesForaneas` → `06_Indices` → `07_Funciones` → `08_Vistas` →
`09_Procedimientos` → `10_Seguridad` → `11_DatosSemilla`. `deploy.ps1` / `deploy.sh` siguen ese orden y
`--listar` lo imprime.

---

## 8. Seguridad

- Token de API de Jira en un almacén de secretos (Windows Credential Manager, Azure Key Vault o variables protegidas del pool de IIS), nunca en `appsettings.json` ni en la base.
- Usuario técnico de Jira **solo lectura**, con acceso a los proyectos que se van a reportar.
- Roles de base: `smc_api` (solo `EXECUTE` en `api`) y `smc_sync` (worker). No se guarda el correo de los clientes.

---

## 9. Decisiones pendientes

1. ~~Worklogs de Automation for Jira~~: resuelto (§5.6). Si en el futuro las personas registran horas a mano, aparecerán solas como `HorasRegistradas`.
2. **Story points.** No se encontró el campo con valor en las muestras. ¿Lo usan? ¿Con qué nombre?
3. ~~Proyectos de prueba~~: resuelto, se excluyen `TS25`, `TSM26` y `TSSM26`. Los temporales (`S22T`, `S2T`) siguen incluidos; se excluyen con `sync.Proyecto_Excluir` si se decide.
4. **Horario laboral para SLA propios.** JSM ya calcula los SLA con su calendario. Si se quieren métricas que JSM no tiene (p. ej. tiempo en cada estado en horario laboral), se agrega un calendario en `cfg`.
