# respaldar-bd.ps1
# Guarda una copia completa de la base en backups\ (RF02: respaldo).
# Esa carpeta NO se sube a Git. Para pasar datos a otra computadora,
# copia el archivo .sql y restauralo alli (ver instrucciones del tutor).
# Uso:  .\scripts\respaldar-bd.ps1
param(
    [string]$Usuario = 'invernadero',
    [string]$Base    = 'monitor_invernadero'
)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\_comun.ps1"

Paso "Respaldo de '$Base'"
$dump = Buscar-Exe "mariadb-dump"
if (-not $dump) { Falla "No encuentro mariadb-dump.exe."; exit 1 }

$pidio = Pedir-PasswordBD $Usuario
try {
    $carpeta = Join-Path $RaizRepo "backups"
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
    $archivo = Join-Path $carpeta ("{0}_{1:yyyyMMdd_HHmmss}.sql" -f $Base, (Get-Date))
    & $dump -u $Usuario --single-transaction --result-file="$archivo" $Base
    if ($LASTEXITCODE -eq 0 -and (Test-Path $archivo) -and (Get-Item $archivo).Length -gt 0) {
        Ok "Respaldo creado: $archivo"
    } else {
        Falla "No se pudo crear el respaldo. Revisa la contrasena y que MariaDB este en Running."
        exit 1
    }
}
finally {
    if ($pidio) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}
