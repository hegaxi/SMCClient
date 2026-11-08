# Base de datos de SMCClient

SQL Server 2017 o posterior (recomendado 2019+). Los scripts están **ordenados por tipo de objeto**
y se ejecutan siempre en el mismo orden: carpeta por carpeta (`00_`, `01_`, …) y, dentro de cada
carpeta, por el número del archivo.

## Orden de ejecución

| Orden | Carpeta | Qué contiene | ¿Se repite en cada despliegue? |
|---|---|---|---|
| 00 | `00_Preparacion` | Validación de versión y bitácora `adm.ScriptEjecutado` | Sí |
| 01 | `01_Esquemas` | `cfg`, `meta`, `raw`, `sync`, `ops`, `rpt`, `api` | Sí (solo crea si falta) |
| 02 | `02_Tipos` | Tipos tabla (TVP) para enviar lotes desde el worker | Sí (solo crea si falta) |
| 03 | `03_Tablas` | Una tabla por archivo, con su llave primaria, en su forma **más reciente** | Sí (solo crea si falta) |
| 04 | `04_Migraciones` | Cambios a tablas que ya existen en producción | **No: una sola vez por base** |
| 05 | `05_LlavesForaneas` | Todas las FK, después de que existen todas las tablas | Sí (solo crea si falta) |
| 06 | `06_Indices` | Índices no agrupados | Sí (solo crea si falta) |
| 07 | `07_Funciones` | Funciones (`CREATE OR ALTER`) | Sí |
| 08 | `08_Vistas` | Vistas `rpt.*` (`CREATE OR ALTER`) | Sí |
| 09 | `09_Procedimientos` | `adm.*` (010), `sync.*` (100-499), `api.*` (500+) | Sí |
| 10 | `10_Seguridad` | Roles `smc_api` y `smc_sync` y sus permisos | Sí |
| 11 | `11_DatosSemilla` | Parámetros, reglas de roles de campo, metadatos de la API | Sí (solo inserta lo que falta) |

Para ver la lista exacta de archivos en orden:

```bash
./deploy.sh --listar        # Linux / CI
./deploy.ps1 -Listar        # Windows
```

## Desplegar

```powershell
# Windows, autenticación integrada
./deploy.ps1 -Server . -Database SMCClient -CrearBd

# Con usuario SQL (la contraseña va en la variable de entorno, no en la línea de comandos)
$env:SQLCMDPASSWORD = '...'
./deploy.ps1 -Server sql01 -Database SMCClient -SqlUser smc_deploy -TrustServerCertificate
```

```bash
SQLCMDPASSWORD='...' ./deploy.sh -S localhost -d SMCClient -U sa -C --crear-bd
```

Después del primer despliegue se configura la instancia de Jira. Lo propio de cada ambiente vive en
`instancias/` (fuera del despliegue ordenado) y se puede repetir:

```bash
sqlcmd -S . -d SMCClient -E -i instancias/smco.sql   # registra smco y excluye TS25, TSM26, TSSM26
```

## Reglas para agregar objetos

1. **Un objeto por archivo**, nombrado `NNN_esquema.Objeto.sql`. El número decide el orden dentro de la carpeta.
2. Todo script debe poder correrse **dos veces seguidas** sin error:
   tablas con `IF OBJECT_ID(...) IS NULL CREATE TABLE`, código con `CREATE OR ALTER`, datos con `MERGE ... WHEN NOT MATCHED`.
3. Una tabla nueva va en `03_Tablas`; sus FK en `05_LlavesForaneas`; sus índices en `06_Indices`.
4. Cambiar una tabla existente: migración en `04_Migraciones` **y** actualizar su `CREATE TABLE` (ver `04_Migraciones/README.md`).
5. Un procedimiento que llama a otro va con un número mayor (evita avisos de dependencia).
6. El esquema `api` es el contrato con el controlador: no se cambian columnas existentes de sus resultados; se agregan al final o se crea `api.Nombre_v2`.
7. Cada procedimiento `api.*` declara en `11_DatosSemilla/090_DescripcionesApi.sql` su `MS_Description`, `smc:permiso` (`lectura` | `admin`; sin él, solo administradores) y `smc:exentoSync` (`1` si debe responder aunque los datos no estén sincronizados).
8. Errores para el usuario: `THROW 5NNNN, 'mensaje', 1`. Si `NNN` es un código HTTP 4xx, la API responde con ese estado (`50404` → 404); si no, 400.

## Pruebas

`tests/010_prueba_integracion.sql` simula al worker con datos ficticios (con la forma real de Jira Cloud) y
verifica 54 condiciones: carga inicial, documento malo en cuarentena, campo eliminado, renombrado, recreado con
otro ID, campo nuevo con backfill, catálogo incompleto, candado entre workers y procedimientos `api.*`.
También verifica la exclusión de proyectos y el cierre de ejecuciones abandonadas por un worker caído.
Se corre sobre una base **recién desplegada**:

```bash
sqlcmd -S localhost -d SMCClient -b -I -x -i tests/010_prueba_integracion.sql
```

## Contrato con el worker (qué documento JSON va en cada entidad)

| Entidad | Endpoint de Jira (configurable en `cfg.EntidadSync`) | `IdExterno` | Contenido de `Json` |
|---|---|---|---|
| `campo` | `GET /rest/api/3/field` | id del campo | un elemento del arreglo |
| `estado` | `GET /rest/api/3/status` | id del estado | un elemento del arreglo |
| `proyecto` | `GET /rest/api/3/project/search` | id del proyecto | un elemento de `values` |
| `issue` | `GET /rest/api/3/search/jql` con `fields=*all` | id del issue | el objeto issue completo |
| `changelog` | `POST /rest/api/3/changelog/bulkfetch` | id del issue | `{"issueId":"…","histories":[…]}` (historial completo) |
| `worklog` | `GET /rest/api/3/worklog/updated` + `POST /rest/api/3/worklog/list` | id del worklog | el objeto worklog |
| `worklog_eliminado` | `GET /rest/api/3/worklog/deleted` | id del worklog | `{"worklogId":…,"updatedTime":…}` |
| `sla` | `GET /rest/servicedeskapi/request/{id}/sla` (todas las páginas) | id del issue | `{"values":[…]}` |

Secuencia por entidad: `sync.Ejecucion_Iniciar` → `sync.Documento_Cargar` (una llamada por página) →
`sync.Procesar_Pendientes` → `sync.Ejecucion_Finalizar`.
