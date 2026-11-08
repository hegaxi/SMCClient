# SMCClient

Consulta de proyectos Scrum (Jira Software) y de mesa de ayuda (Jira Service Management):
tickets, historias, tiempo invertido, SLA y avance de sprints.

| Parte | Carpeta | Estado |
|---|---|---|
| Base de datos (SQL Server 2017+, recomendado 2019+) | [`db/`](db/README.md) | Lista |
| Worker de sincronización Jira → SQL Server (.NET 8) | `src/SMCClient.Sync`, `src/SMCClient.Worker` | Listo |
| Controlador único (ASP.NET Core) | — | Pendiente |
| Interfaz (React) | — | Pendiente |

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
| `DuracionCandadoSegundos` | 900 | Vigencia del candado por fuente (se renueva durante cargas largas) |
| `ConciliacionCadaHoras` | 24 | Cada cuánto se detectan issues borrados en Jira |
| `Fuentes[n].MaxConcurrencia` | 4 | Peticiones simultáneas a Jira para los SLA |
| `Fuentes[n].TimeoutSegundos` | 100 | Tiempo máximo de cada intento HTTP (con 6 reintentos ante 429/5xx, respetando `Retry-After`) |

Las frecuencias por entidad, los endpoints de Jira y los proyectos excluidos están en la base
(`cfg.EntidadSync`, `cfg.ProyectoExcluido`), no en el worker.

## Pruebas

```bash
./db/deploy.sh -S localhost -d SMCClient -U sa -C --crear-bd          # SQLCMDPASSWORD en el entorno
sqlcmd -S localhost -d SMCClient -U sa -C -b -I -x -i db/tests/010_prueba_integracion.sql
SMC_TEST_SQL="Server=localhost;Database=SMCClient;User Id=sa;Password=...;TrustServerCertificate=true" dotnet test
```

Sin `SMC_TEST_SQL` las pruebas de integración del worker se omiten y solo corren las unitarias.
