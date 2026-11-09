<#
.SYNOPSIS
  Despliega la base de datos de SMCClient ejecutando los scripts EN ORDEN
  (carpetas NN_* en orden numérico; dentro de cada una, archivos en orden de nombre).
.DESCRIPTION
  Todos los scripts son idempotentes, salvo 04_Migraciones, que se ejecuta una sola vez
  por base de datos (bitácora en adm.ScriptEjecutado). Requiere sqlcmd en el PATH.
.EXAMPLE
  ./deploy.ps1 -Server . -Database SMCClient -CrearBd
.EXAMPLE
  $env:SQLCMDPASSWORD = '...'; ./deploy.ps1 -Server sql01 -Database SMCClient -SqlUser smc_deploy -TrustServerCertificate
.EXAMPLE
  ./deploy.ps1 -Listar
#>
param(
    [string]$Server,
    [string]$Database,
    [string]$SqlUser,                 # sin usuario: autenticación de Windows. Contraseña en $env:SQLCMDPASSWORD
    [switch]$TrustServerCertificate,
    [switch]$CrearBd,
    [switch]$Listar,
    [string]$Sqlcmd = 'sqlcmd'
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

$scripts = Get-ChildItem -Path $dir -Directory | Where-Object Name -match '^\d\d_' | Sort-Object Name |
    ForEach-Object { Get-ChildItem -Path $_.FullName -Filter *.sql -File | Sort-Object Name } |
    ForEach-Object { $_.FullName.Substring($dir.Length + 1).Replace('\', '/') }

if ($Listar) { $scripts; return }
if (-not $Server -or -not $Database) { throw 'Faltan -Server y -Database.' }

# -f 65001: los scripts están en UTF-8 sin BOM; sin esto sqlcmd los lee con la página de códigos de Windows
# y los acentos quedan mal en la base (p. ej. "sincronizaciÃ³n").
$base = @('-S', $Server, '-b', '-I', '-x', '-f', '65001')
if ($SqlUser) { $base += @('-U', $SqlUser) } else { $base += '-E' }
if ($TrustServerCertificate) { $base += '-C' }

function Invoke-Sql([string[]]$extra) {
    & $Sqlcmd @base @extra
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd terminó con código $LASTEXITCODE" }
}
function Get-Escalar([string]$query) {
    (& $Sqlcmd @base -d $Database -h -1 -W -Q "SET NOCOUNT ON; $query" | Out-String).Trim()
}

if ($CrearBd) {
    $db = $Database.Replace("'", "''"); $dbq = $Database.Replace(']', ']]')
    # Si la crea una cuenta de Windows (DOMINIO\usuario), el dueño pasa a sa: los procedimientos WITH EXECUTE AS OWNER
    # (búsqueda avanzada) no deben depender de que el controlador de dominio responda (error 15404 sin VPN).
    Invoke-Sql @('-d', 'master', '-Q', "IF DB_ID(N'$db') IS NULL BEGIN CREATE DATABASE [$dbq]; IF SUSER_SNAME() LIKE N'%\%' ALTER AUTHORIZATION ON DATABASE::[$dbq] TO sa; END;")
}

foreach ($rel in $scripts) {
    $path = Join-Path $dir $rel
    $hash = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $ruta = $rel.Replace("'", "''")
    if ($rel -like '04_Migraciones/*') {
        if ((Get-Escalar "SELECT COUNT(*) FROM adm.ScriptEjecutado WHERE Ruta = N'$ruta';") -ne '0') {
            Write-Host "  (omitido, ya aplicado) $rel"; continue
        }
    }
    Write-Host "  -> $rel"
    Invoke-Sql @('-d', $Database, '-i', $path)
    Invoke-Sql @('-d', $Database, '-Q', @"
SET NOCOUNT ON;
IF OBJECT_ID('adm.ScriptEjecutado') IS NOT NULL
MERGE adm.ScriptEjecutado AS t USING (SELECT N'$ruta' AS Ruta, '$hash' AS Hash) AS s ON t.Ruta = s.Ruta
WHEN MATCHED THEN UPDATE SET Hash = s.Hash, Ejecuciones = t.Ejecuciones + 1, Ultima = SYSDATETIMEOFFSET()
WHEN NOT MATCHED THEN INSERT (Ruta, Hash) VALUES (s.Ruta, s.Hash);
"@) | Out-Null
}
Write-Host "Despliegue terminado: $($scripts.Count) scripts."
