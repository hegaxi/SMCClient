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
    [switch]$PermitirMigracionEditada,  # aplicar aunque una migración ya aplicada haya cambiado (solo comentarios)
    [string]$Sqlcmd = 'sqlcmd'
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot

# Orden ordinal (igual que deploy.sh con LC_ALL=C y la prueba .NET), no el de la cultura de Windows.
function Get-Ordenados($items) { $a = [string[]]@($items | ForEach-Object Name); [Array]::Sort($a, [StringComparer]::Ordinal); $a }
$scripts = foreach ($carpeta in (Get-Ordenados (Get-ChildItem -Path $dir -Directory | Where-Object Name -match '^\d\d_'))) {
    foreach ($archivo in (Get-Ordenados (Get-ChildItem -Path (Join-Path $dir $carpeta) -Filter *.sql -File))) { "$carpeta/$archivo" }
}

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
    # Si sqlcmd falla (red, permisos) se detiene: antes una falla se leía como "ya aplicado" y la migración se omitía.
    $r = (& $Sqlcmd @base -d $Database -h -1 -W -Q "SET NOCOUNT ON; $query" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd terminó con código $LASTEXITCODE al consultar: $query" }
    $r
}
function Get-HashNormalizado([string]$path) {
    # Sin retornos de carro: el mismo hash con CRLF o LF (git en Windows cambia los finales de línea). Igual que deploy.sh.
    $bytes = [IO.File]::ReadAllBytes($path) | Where-Object { $_ -ne 13 }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash([byte[]]$bytes) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}

if ($CrearBd) {
    $db = $Database.Replace("'", "''"); $dbq = $Database.Replace(']', ']]')
    # Si la crea una cuenta de Windows (DOMINIO\usuario), el dueño pasa a sa: los procedimientos WITH EXECUTE AS OWNER
    # (búsqueda avanzada) no deben depender de que el controlador de dominio responda (error 15404 sin VPN).
    Invoke-Sql @('-d', 'master', '-Q', "IF DB_ID(N'$db') IS NULL BEGIN CREATE DATABASE [$dbq]; IF SUSER_SNAME() LIKE N'%\%' ALTER AUTHORIZATION ON DATABASE::[$dbq] TO sa; END;")
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "smc-deploy-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    foreach ($rel in $scripts) {
        $path = Join-Path $dir $rel
        $hash = Get-HashNormalizado $path
        $hashCrudo = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
        $ruta = $rel.Replace("'", "''")
        $registro = @"
SET NOCOUNT ON;
IF OBJECT_ID('adm.ScriptEjecutado') IS NOT NULL
MERGE adm.ScriptEjecutado AS t USING (SELECT N'$ruta' AS Ruta, '$hash' AS Hash) AS s ON t.Ruta = s.Ruta
WHEN MATCHED THEN UPDATE SET Hash = s.Hash, Ejecuciones = t.Ejecuciones + 1, Ultima = SYSDATETIMEOFFSET()
WHEN NOT MATCHED THEN INSERT (Ruta, Hash) VALUES (s.Ruta, s.Hash);
"@
        if ($rel -like '04_Migraciones/*') {
            $previo = Get-Escalar "SELECT ISNULL((SELECT Hash FROM adm.ScriptEjecutado WHERE Ruta = N'$ruta'), '-');"
            if ($previo -ne '-') {
                # Una migración aplicada no se edita (04_Migraciones/README.md, regla 4): el cambio no llegaría a las
                # bases donde ya corrió. Se acepta el hash anterior al normalizado (con CRLF) para bases viejas.
                # Un registro sin hash (p. ej. 'manual', anotado a mano) no se puede comparar: solo se avisa.
                if ($previo -notmatch '^[0-9a-f]{64}$') {
                    Write-Warning "La migración $rel está registrada sin hash ('$previo'); no se puede verificar si cambió."
                } elseif ($previo -ne $hash -and $previo -ne $hashCrudo -and -not $PermitirMigracionEditada) {
                    throw "La migración $rel cambió después de aplicarse (hash $previo). Escribe una migración nueva, o usa -PermitirMigracionEditada si el cambio es solo de comentarios."
                }
                Write-Host "  (omitido, ya aplicado) $rel"; continue
            }
            # Toda la migración y su registro en una transacción (misma conexión): si un lote falla, sqlcmd sale (-b),
            # la conexión se cierra y SQL Server deshace todo; no queda aplicada a medias ni sin registrar.
            $ini = Join-Path $tmp 'ini.sql'; $fin = Join-Path $tmp 'fin.sql'
            [IO.File]::WriteAllText($ini, "SET XACT_ABORT ON;`r`nBEGIN TRANSACTION;`r`nGO`r`n")
            [IO.File]::WriteAllText($fin, "$registro`r`nCOMMIT TRANSACTION;`r`nGO`r`n")
            Write-Host "  -> $rel (migración, en transacción)"
            Invoke-Sql @('-d', $Database, '-i', "$ini,$path,$fin")
            continue
        }
        Write-Host "  -> $rel"
        Invoke-Sql @('-d', $Database, '-i', $path)
        Invoke-Sql @('-d', $Database, '-Q', $registro) | Out-Null
    }
} finally {
    Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
}
Write-Host "Despliegue terminado: $($scripts.Count) scripts."
