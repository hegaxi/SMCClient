# SMCClient

Consulta de proyectos Scrum (Jira Software) y de mesa de ayuda (Jira Service Management):
tickets, historias, tiempo invertido, SLA y avance de sprints.

| Parte | Carpeta | Estado |
|---|---|---|
| Base de datos (SQL Server 2017+, recomendado 2019+) | [`db/`](db/README.md) | Lista |
| Worker de sincronización Jira → SQL Server (.NET 8) | `src/SMCClient.Sync`, `src/SMCClient.Worker` | Listo |
| API con un solo controlador (ASP.NET Core 8) | `src/SMCClient.Api` | Lista |
| Interfaz (React 19 + Vite) | `web/` | Lista |

La arquitectura, cómo resiste cambios en Jira y cómo funciona la sincronización están en
[`docs/arquitectura.md`](docs/arquitectura.md).

## Puesta en marcha

### 1. Base de datos

```powershell
cd db
./deploy.ps1 -Server . -Database SMCClient -CrearBd
sqlcmd -S . -d SMCClient -E -i instancias/smco.sql     # registra smco.atlassian.net y excluye los proyectos de prueba
```

### 2. Worker

El worker necesita un **usuario técnico de Jira con permiso de solo lectura** sobre los proyectos a reportar
y su **API token** (https://id.atlassian.com/manage-profile/security/api-tokens).
El token **nunca** va en `appsettings.json`:

```powershell
cd src/SMCClient.Worker
dotnet user-secrets set "SmcSync:Fuentes:0:Usuario" "usuario.tecnico@empresa.com"
dotnet user-secrets set "SmcSync:Fuentes:0:Token"   "<api token>"
dotnet run
```

En un servidor se usan variables de entorno (o el almacén de secretos de la organización):

```powershell
setx SmcSync__Fuentes__0__Usuario "usuario.tecnico@empresa.com" /M
setx SmcSync__Fuentes__0__Token   "<api token>" /M
setx ConnectionStrings__SMCClient "Server=sql01;Database=SMCClient;Integrated Security=true;TrustServerCertificate=true" /M
```

Instalarlo como servicio de Windows:

```powershell
dotnet publish src/SMCClient.Worker -c Release -o C:\SMCClient\worker
sc.exe create "SMCClient Sync" binPath= "C:\SMCClient\worker\SMCClient.Worker.exe" start= delayed-auto
sc.exe start "SMCClient Sync"
```

Si el token falta, el worker no arranca y lo dice. Al arrancar hace la sincronización completa; mientras tanto
`api.Sync_Estado` devuelve `DatosVigentes = 0` (el controlador responderá 503).

### Configuración (`SmcSync` en appsettings)

| Clave | Por omisión | Qué hace |
|---|---|---|
| `IntervaloRevisionSegundos` | 60 | Cada cuánto revisa qué entidades vencieron y la cola de solicitudes |
| `MinutosReintentoTrasError` | 5 | Espera antes de reintentar una entidad que falló (no insiste contra un Jira caído) |
| `MaxPendientesPorCorrida` | 2000 | Issues pendientes de historial / SLA (`sync.IssuePendiente`) que se piden por corrida |
| `MaxPadresPorCorrida` | 500 | Padres o épicas faltantes que se traen por clave en cada ronda |
| `DuracionCandadoSegundos` | 900 | Vigencia del candado por fuente (se renueva durante cargas largas) |
| `ConciliacionCadaHoras` | 24 | Cada cuánto se detectan issues borrados en Jira |
| `Fuentes[n].MaxConcurrencia` | 4 | Peticiones simultáneas a Jira para los SLA |
| `Fuentes[n].TimeoutSegundos` | 100 | Tiempo máximo de cada intento HTTP (con 6 reintentos ante 429/5xx, respetando `Retry-After`) |

Las frecuencias por entidad, los endpoints de Jira y los proyectos excluidos están en la base
(`cfg.EntidadSync`, `cfg.ProyectoExcluido`), no en el worker.

### 3. API

```powershell
cd src/SMCClient.Api
dotnet run --environment Development      # http://localhost:5xxx (pide iniciar sesión)
```

| Método | Ruta | Qué hace |
|---|---|---|
| `GET` | `/api/procedimientos` | Procedimientos del esquema `api` que el usuario puede ejecutar, con parámetros (tipo, longitud, opcional, descripción) y columnas del resultado |
| `GET` | `/api/procedimientos/{nombre}` | Metadatos de uno |
| `POST` | `/api/procedimientos/{nombre}` | Lo ejecuta. Cuerpo: `{"Proyecto":"SMC26","Pagina":1}`. Respuesta: `{"resultados":[{"columnas":[…],"filas":[{…}],"truncado":false}],"salida":{}}` |
| `GET` | `/salud` | La API responde y llega a SQL Server (anónimo, para monitoreo) |

Respuestas de error (`application/problem+json`, con `codigo`):

| Estado | `codigo` | Cuándo |
|---|---|---|
| 400 | `parametro.invalido` | Parámetro faltante, desconocido, de otro tipo o demasiado largo (detalle en `errors`) |
| 400 / 404 / 409… | `sql.5NNNN` | `THROW` de negocio del procedimiento. Si los tres últimos dígitos son un 4xx se usa ese estado (`THROW 50404` → 404) |
| 401 | `sesion.requerida` / `sesion.invalida` | Sin sesión, o la sesión se cerró (cambio de contraseña, usuario desactivado) |
| 403 | `procedimiento.sin_permiso` / `contrasena.debe_cambiar` | Sus roles no incluyen ese procedimiento / debe cambiar su contraseña primero |
| 404 | `procedimiento.no_existe` | No es un procedimiento del esquema `api` |
| 503 | `sync.pendiente` | Los datos de Jira aún no están sincronizados (encabezado `Retry-After`); no aplica a los procedimientos `smc:exentoSync = 1` |
| 504 | `sql.timeout` | La consulta excedió `Api:TimeoutSqlSegundos` |

**Usuarios y permisos (en SQL Server).** No se usa Active Directory: los usuarios, sus contraseñas y sus roles viven
en la base (esquema `seg`) y se administran desde la aplicación (Administración). La contraseña nunca llega en claro a
SQL Server: la API calcula su hash (PBKDF2-SHA256, 600 000 iteraciones) y la base aplica las reglas:

| Regla (en SQL Server) | Dónde |
|---|---|
| Longitud mínima (`cfg.Parametro ContrasenaLongitudMinima`, 10) | `seg.Contrasena_Establecer` |
| Bloqueo tras 5 intentos fallidos durante 15 min (`IntentosFallidosMaximos`, `MinutosBloqueo`) | `seg.Login_Resultado` |
| Cambio obligatorio después de que un administrador la restablece | `seg.Contrasena_Establecer`, `seg.Permisos_Usuario` |
| Solo un administrador restablece la contraseña de otro; para la propia se pide la actual | `seg.Contrasena_Establecer` |
| Cambiar la contraseña o desactivar a alguien cierra sus demás sesiones (sello de seguridad) | `seg.Contrasena_Establecer`, `api.Usuario_Guardar` |
| Nadie se quita a sí mismo la administración; siempre queda un administrador activo | `api.Usuario_Guardar`, `api.Rol_Guardar` |
| Qué puede ejecutar cada usuario (por categoría `lectura` / `admin` o por procedimiento `api.X`) | `seg.Permisos_Usuario` |
| Todo queda en `seg.Auditoria` (sin datos de contraseñas) | `seg.Auditoria_Registrar` |

Primer administrador, después de desplegar la base (pide la contraseña en la consola; usa una conexión con permisos de
administración porque la API no puede crear administradores):

```powershell
dotnet SMCClient.Api.dll crear-administrador --usuario admin --nombre "Administrador" --cadena "Server=.;Database=SMCClient;Integrated Security=true;TrustServerCertificate=true"
```

Sirve también para recuperar el acceso si todos los administradores olvidan su contraseña.

Endpoints de sesión (`/api/sesion`): `GET` (sesión actual), `POST iniciar`, `POST cerrar`, `POST cambiar-contrasena`,
`POST restablecer-contrasena` (administradores). La cookie es `HttpOnly`, `SameSite=Strict` y `Secure` fuera de desarrollo;
toda petición que modifica debe traer el encabezado `X-SMC-Solicitud` (protección CSRF) y el inicio de sesión tiene
límite de intentos por IP.

**Publicación en IIS**: `dotnet publish src/SMCClient.Api -c Release -o C:\SMCClient\api`, sitio con el Hosting Bundle de
.NET 8 y **HTTPS obligatorio** (la cookie de sesión solo viaja por HTTPS). Autenticación **Anónima** habilitada en IIS
(la aplicación maneja su propio inicio de sesión). El pool corre con una cuenta que en SQL Server solo tiene el rol `smc_api`.

**Agregar una consulta nueva** no requiere tocar la API ni React: se crea el procedimiento en `db/09_Procedimientos`
(esquema `api`) y sus propiedades en `db/11_DatosSemilla/090_DescripcionesApi.sql` (`smc:titulo`, `MS_Description`,
`smc:permiso`...). Con `smc:permiso = lectura` lo ven de inmediato todos los roles con la categoría `lectura`; sin
`smc:permiso` queda solo para administradores.

### 4. Interfaz (React)

```bash
cd web
npm ci
npm run dev          # http://localhost:5173, envía /api a la API en http://localhost:5080
```

La API en desarrollo se levanta con `ASPNETCORE_URLS=http://localhost:5080 dotnet run --project src/SMCClient.Api --environment Development`.
Para producción no hay que publicar nada aparte: `dotnet publish src/SMCClient.Api` construye la interfaz y la deja en
`wwwroot` (requiere Node 20+ en la máquina que publica).

Qué hace:

- **Inicio de sesión** con usuario y contraseña de la base; cambio obligatorio de contraseña tras un restablecimiento; "Cambiar contraseña" y "Salir" en el encabezado; los administradores ven "Restablecer contraseña".
- **Sincroniza antes de todo.** Mientras alguna fuente no tenga datos vigentes muestra el avance por tipo de dato y se abre sola al terminar. Si una consulta responde 503, vuelve a esa pantalla.
- **Se arma con los metadatos de la base.** Menú (`smc:titulo`, agrupado en Consultas / Sincronización / Administración según `smc:permiso` y en subgrupos según el prefijo del nombre, con los listados antes que las acciones; ver `web/src/menu.ts`), formularios por tipo de parámetro, listas (`smc:opciones`), títulos de cada resultado (`smc:resultados`). Un procedimiento nuevo en la base aparece en el menú sin tocar React.
- **Consultas.** Corren solas al abrirlas si no les falta nada obligatorio; las acciones (`smc:accion`) nunca, y piden confirmación. Tablas ordenables, descarga CSV, paginación, la clave de un issue abre su detalle, los filtros quedan en la dirección (se pueden compartir y funciona "Atrás").
- Accesible (etiquetas, errores ligados a cada campo, navegación con teclado), adaptable a pantallas chicas y con modo oscuro.

### 5. Filtros y tableros

- **Guardar como filtro**: en cualquier consulta, después de elegir los valores. Las fechas se pueden guardar fijas o
  **relativas** (hoy, hace 7 / 30 días, inicio de semana, de mes, del mes anterior, fin del mes anterior, inicio del año),
  para que el tablero siempre muestre datos actuales. Un filtro puede ser privado o compartido.
- **Tableros**: en el menú *Tableros* → *Nuevo tablero*. Se comparten con usuarios o roles (`ana, rol:Consulta`).
  Cada widget usa un filtro y se muestra como **indicador** (un número: conteo, suma, promedio, máximo, mínimo o primer
  valor), **barras** (agrupadas por una columna, con *Ver tabla*) o **tabla**. Ancho de 1/4 a completo; se ordenan con ↑ ↓.
- **Para cada usuario**: quien recibe un tablero lo ve con *sus* permisos (si no puede ejecutar la consulta de un widget,
  el widget dice "Sin permiso") y puede elegirlo como **pantalla de inicio** (*Usar como inicio*).
- Las reglas están en SQL Server (`dash.*`, `api.Filtro_*`, `api.Tablero_*`, `api.Widget_*`): solo el propietario modifica,
  no se guardan filtros de acciones ni de consultas no permitidas, no se borra un filtro que usa un widget, etc.

### 6. Tiempo reportado en Scrum

En Scrum las personas registran el tiempo en las **subtareas**. *Horas por sprint* da las horas por sprint y persona
(registradas y automáticas), *Avance de sprints* incluye las horas registradas dentro de las fechas de cada sprint, el
detalle de una historia suma y lista las de sus subtareas, y la búsqueda avanzada tiene *Horas registradas (con
subtareas)*, *Es subtarea*, *Registró tiempo (persona)* y *Fecha de registro de tiempo*.
Las **épicas** suman las horas de sus tareas y de las subtareas de éstas: *Avance de épicas* da tareas terminadas, % de
avance, story points, estimación y horas; *Horas por persona* se puede filtrar por épica, y la búsqueda tiene la columna
y el criterio *Épica*.
Detalle: [`docs/arquitectura.md` §5.6.1 y §5.6.2](docs/arquitectura.md).

### 8. Consultas personalizadas, clientes y comentarios

- **Consultas personalizadas**: un administrador arma una búsqueda avanzada y la publica con nombre (*Publicar como consulta
  personalizada*), compartida con usuarios o roles. Aparece en el menú de quien tiene acceso.
- **Clientes**: se les da el rol *Cliente* (externo) y su organización de mesa de ayuda (*Organizaciones de un cliente*). Solo
  ven las consultas que se les compartieron, con los tickets de su organización; nada de los reportes internos.
- **Comentarios**: se sincronizan (públicos e internos) y se ven en el detalle y en la búsqueda.
- **Frecuencia de sincronización**: el administrador la cambia por tipo de dato en *Cambiar frecuencia de sincronización*.

### 7. Búsqueda avanzada (como el navegador de issues de Jira)

*Consultas → Búsqueda avanzada*: texto libre, criterios sobre **cualquier** campo — también los personalizados de Jira,
que aparecen solos al sincronizarse — con operadores según el tipo (es alguno de / ninguno de, contiene, mayor que, entre,
desde / hasta con fechas fijas o relativas, está vacío…), columnas a elegir y reordenar, orden por encabezado y paginación.
La búsqueda queda en la dirección (se comparte el enlace) y se puede **guardar como filtro** para usarla en un widget.
En los tableros, las barras e indicadores de una búsqueda se calculan en SQL Server sobre **todos** los issues (contar, sumar,
promediar… agrupando por cualquier campo), sin el tope de filas de una consulta.
Detalle técnico y seguridad del SQL dinámico: [`docs/arquitectura.md` §5.9](docs/arquitectura.md).

## Pruebas

```bash
./db/deploy.sh -S localhost -d SMCClient -U sa -C --crear-bd          # SQLCMDPASSWORD en el entorno
sqlcmd -S localhost -d SMCClient -U sa -C -b -I -x -i db/tests/010_prueba_integracion.sql
SMC_TEST_SQL="Server=localhost;User Id=sa;Password=...;TrustServerCertificate=true" dotnet test
```

Interfaz: `cd web && npm test` (componentes) y `npm run e2e` (Chromium contra la API corriendo en `BASE_URL`; ver `web/e2e/flujo.mjs`).

Con `SMC_TEST_SQL` (servidor, **sin** `Database`) cada suite crea una base desechable con los scripts de `db/` en orden,
corre sus pruebas y la borra; la de la API además crea un login que solo tiene el rol `smc_api`.
Sin `SMC_TEST_SQL` solo corren las pruebas unitarias.
