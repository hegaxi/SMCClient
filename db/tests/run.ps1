<#
.SYNOPSIS
  Corre todas las pruebas SQL (db/tests/*.sql, en orden) sobre una base DESECHABLE: la crea, despliega todo con
  deploy.ps1 -CrearBd, ejecuta cada prueba y la borra al final, aunque una prueba falle. No toca la base de trabajo.
.EXAMPLE
  ./run.ps1                       # instancia local, autenticación de Windows
.EXAMPLE
  ./run.ps1 -Server sql01 -SqlUser smc_ci -TrustServerCertificate   # contraseña en $env:SQLCMDPASSWORD
.EXAMPLE
  ./run.ps1 -Conservar            # deja la base para revisar qué pasó
#>
param(
    [string]$Server = '.',
    [string]$Database = "SMCClient_Pruebas_$PID",
    [string]$SqlUser,
    [switch]$TrustServerCertificate,
    [switch]$Conservar,
    [string]$Sqlcmd = 'sqlcmd'
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$base = @('-S', $Server, '-b', '-I', '-x', '-f', '65001')
if ($SqlUser) { $base += @('-U', $SqlUser) } else { $base += '-E' }
if ($TrustServerCertificate) { $base += '-C' }

$pruebas = [string[]]@(Get-ChildItem -Path $dir -Filter *.sql -File | ForEach-Object Name)
[Array]::Sort($pruebas, [StringComparer]::Ordinal)   # el orden importa: 050/060/070 usan datos de 010, 080 de 020

$deploy = @{ Server = $Server; Database = $Database; CrearBd = $true; Sqlcmd = $Sqlcmd }
if ($SqlUser) { $deploy.SqlUser = $SqlUser }
if ($TrustServerCertificate) { $deploy.TrustServerCertificate = $true }

$fallo = $null
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    Write-Host "== Desplegando en $Database ..."
    & (Join-Path $dir '..\deploy.ps1') @deploy | Out-Null
    foreach ($p in $pruebas) {
        Write-Host "== $p"
        & $Sqlcmd @base -d $Database -i (Join-Path $dir $p) | Where-Object { $_ -match '^(ok|FALL|TODAS)' } | ForEach-Object { "   $_" }
        if ($LASTEXITCODE -ne 0) { $fallo = $p; break }
    }
} finally {
    if (-not $Conservar) {
        $db = $Database.Replace(']', ']]'); $lit = $Database.Replace("'", "''")
        & $Sqlcmd @base -d master -Q "IF DB_ID(N'$lit') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END;" | Out-Null
    } else { Write-Host "Base conservada: $Database" }
}
if ($fallo) { Write-Host "FALLÓ: $fallo ($([int]$sw.Elapsed.TotalSeconds) s)" -ForegroundColor Red; exit 1 }
Write-Host "Todas las pruebas SQL pasaron: $($pruebas.Count) archivos ($([int]$sw.Elapsed.TotalSeconds) s)." -ForegroundColor Green
