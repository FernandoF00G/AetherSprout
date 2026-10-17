# actualizar-bd.ps1
# Trae lo ultimo del repositorio y aplica a MariaDB las migraciones
# (database\migraciones\*.sql) que esta computadora aun no tenga.
# Se puede ejecutar todas las veces que quieras: no repite lo ya aplicado.
# Uso:  .\scripts\actualizar-bd.ps1
param(
    [string]$Usuario = 'invernadero',
    [string]$Base    = 'monitor_invernadero',
    [switch]$SinPull
)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\_comun.ps1"

Paso "Actualizar base de datos '$Base'"

$mariadb = Buscar-Exe "mariadb"
if (-not $mariadb) { Falla "No encuentro mariadb.exe. Ejecuta primero scripts\instalar.ps1"; exit 1 }

if (-not $SinPull) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "git pull ..."
        git -C $RaizRepo pull
    } else { Aviso "Git no se reconoce; me salto el git pull." }
}

$pidio = Pedir-PasswordBD $Usuario
try {
    & $mariadb -u $Usuario $Base -e "SELECT 1" *> $null
    if ($LASTEXITCODE -ne 0) {
        Falla "No pude conectar como '$Usuario' a '$Base'. Revisa la contrasena y que el servicio MariaDB este en Running."
        exit 1
    }
    Ok "Conexion correcta"

    & $mariadb -u $Usuario $Base -e "CREATE TABLE IF NOT EXISTS esquema_version (archivo VARCHAR(200) NOT NULL PRIMARY KEY, aplicado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;"
    $aplicadas = @(& $mariadb -u $Usuario $Base -N -B -e "SELECT archivo FROM esquema_version")

    $carpeta  = Join-Path $RaizRepo "database\migraciones"
    $archivos = @(Get-ChildItem $carpeta -Filter "*.sql" -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($archivos.Count -eq 0) { Aviso "No hay archivos en $carpeta"; exit 0 }

    foreach ($a in $archivos) {
        if ($aplicadas -contains $a.Name) { Ok "$($a.Name): ya aplicada"; continue }
        Write-Host "Aplicando $($a.Name) ..."
        Get-Content -Raw $a.FullName | & $mariadb -u $Usuario $Base
        if ($LASTEXITCODE -eq 0) {
            & $mariadb -u $Usuario $Base -e "INSERT INTO esquema_version (archivo) VALUES ('$($a.Name)')"
            Ok "$($a.Name): aplicada"
        } else {
            Falla "$($a.Name) fallo. Me detengo para no dejar la base a medias. Copia el error completo."
            exit 1
        }
    }

    Paso "Estado actual"
    & $mariadb -u $Usuario $Base -e "DESCRIBE lectura; SELECT COUNT(*) AS lecturas_guardadas FROM lectura;"
}
finally {
    if ($pidio) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}
