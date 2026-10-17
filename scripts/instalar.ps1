# =====================================================================
# instalar.ps1 - Entorno de desarrollo AetherSprout (Sprint 1)
# Windows 10/11. Ejecutar en PowerShell COMO ADMINISTRADOR.
# Se puede ejecutar varias veces sin romper nada.
#
# Instala: Git, VS Code, PHP 8.2, MariaDB
# Configura: pdo_mysql en php.ini, servicio MariaDB, base y usuario
#            del proyecto, regla de firewall (puerto 8000, red privada)
# Opcional: clona el repositorio y fija tu identidad de Git (solo local)
#
# NO instala ESP-IDF (se instala con la extension de VS Code).
# NO guarda contrasenas en el script: las pide al ejecutarse.
# (Archivo en ASCII a proposito, para evitar problemas de codificacion.)
# =====================================================================

$ErrorActionPreference = 'Continue'

function Paso($t)  { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "[OK] $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "[!]  $t" -ForegroundColor Yellow }
function Falla($t) { Write-Host "[X]  $t" -ForegroundColor Red }

function Actualizar-Path {
    $m = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $u = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$m;$u"
}

function Instalar-Winget($id) {
    Write-Host "Instalando $id ..."
    winget install --id $id -e --accept-package-agreements --accept-source-agreements
    # -1978335189 = "ya esta instalado y no hay version nueva": no es error
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        Aviso "winget devolvio el codigo $LASTEXITCODE para $id. Revisa el mensaje de arriba."
    } else {
        Ok "$id listo"
    }
}

function Texto-Plano([System.Security.SecureString]$s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# ---------- 0. Comprobaciones ----------
Paso "0. Comprobaciones"
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) { Falla "Abre PowerShell como administrador y vuelve a ejecutar."; exit 1 }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Falla "No se encontro winget. Actualiza 'Instalador de aplicacion' en Microsoft Store."; exit 1
}
Ok "Administrador y winget disponibles"

# ---------- 1. Programas ----------
Paso "1. Instalando programas"
Instalar-Winget "Git.Git"
Instalar-Winget "Microsoft.VisualStudioCode"
Instalar-Winget "PHP.PHP.8.2"
Instalar-Winget "MariaDB.Server"
Actualizar-Path

# ---------- 2. PHP: activar pdo_mysql ----------
Paso "2. Configurando PHP (php.ini)"
$phpDir = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Directory -Filter "PHP.PHP.8.2_*" -ErrorAction SilentlyContinue |
          Select-Object -First 1
if (-not $phpDir) {
    Falla "No encontre la carpeta de PHP en WinGet\Packages. Cierra esta ventana, abre otra como administrador y repite."
} else {
    $ini = Join-Path $phpDir.FullName "php.ini"
    $dev = Join-Path $phpDir.FullName "php.ini-development"
    if (-not (Test-Path $ini)) {
        if (Test-Path $dev) { Copy-Item $dev $ini; Ok "php.ini creado desde php.ini-development" }
        else { Falla "No existe php.ini-development en $($phpDir.FullName)" }
    }
    if (Test-Path $ini) {
        $c = Get-Content $ini
        $c = $c -replace '^\s*;\s*extension_dir\s*=\s*"ext"\s*$', 'extension_dir = "ext"'
        $c = $c -replace '^\s*;\s*extension\s*=\s*pdo_mysql\s*$', 'extension=pdo_mysql'
        $c = $c -replace '^\s*;\s*extension\s*=\s*mysqli\s*$', 'extension=mysqli'
        Set-Content -Path $ini -Value $c
        Ok "Extensiones activadas en $ini"
    }
}

# ---------- 3. MariaDB: servicio ----------
Paso "3. MariaDB (servicio)"
$mdbRoot = Get-ChildItem "C:\Program Files" -Directory -Filter "MariaDB*" -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName "bin\mariadbd.exe") } |
           Sort-Object Name -Descending | Select-Object -First 1
if (-not $mdbRoot) {
    Falla "No encontre MariaDB en C:\Program Files. Revisa la instalacion de winget."; exit 1
}
$bin     = Join-Path $mdbRoot.FullName "bin"
$data    = Join-Path $mdbRoot.FullName "data"
$mariadb = Join-Path $bin "mariadb.exe"
Ok "MariaDB en $($mdbRoot.FullName)"

$svc = Get-CimInstance Win32_Service | Where-Object { $_.PathName -match "mariadbd" } | Select-Object -First 1
if (-not $svc) {
    Aviso "No hay servicio de MariaDB. Lo registro."
    if (Test-Path (Join-Path $data "mysql")) {
        # Carpeta de datos ya inicializada: solo registrar el servicio
        $myini = Join-Path $data "my.ini"
        & (Join-Path $bin "mariadbd.exe") --install MariaDB --defaults-file="$myini"
    } else {
        # Carpeta de datos vacia: inicializar y registrar (root queda sin contrasena)
        & (Join-Path $bin "mariadb-install-db.exe") --service=MariaDB
    }
    $svc = Get-CimInstance Win32_Service | Where-Object { $_.PathName -match "mariadbd" } | Select-Object -First 1
}
if (-not $svc) { Falla "No se pudo registrar el servicio. Copia el mensaje de error y pidele ayuda al tutor."; exit 1 }

$svcName = $svc.Name
Set-Service $svcName -StartupType Automatic
if ((Get-Service $svcName).Status -ne 'Running') { Start-Service $svcName }
Start-Sleep -Seconds 3
if ((Get-Service $svcName).Status -eq 'Running') { Ok "Servicio $svcName en ejecucion (inicio automatico)" }
else { Falla "El servicio no arranco. Revisa los archivos .err en $data"; exit 1 }

# PATH de usuario con la carpeta bin de MariaDB
$pathUsuario = [Environment]::GetEnvironmentVariable("Path", "User")
if ($pathUsuario -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$pathUsuario;$bin", "User")
    Ok "MariaDB agregado al PATH (abre una terminal nueva para usarlo)"
}
Actualizar-Path

# ---------- 4. Contrasena de root, base y usuario del proyecto ----------
Paso "4. Base de datos del proyecto"
$env:MYSQL_PWD = ""
& $mariadb -u root -e "SELECT 1" *> $null
$rootEnBlanco = ($LASTEXITCODE -eq 0)

if ($rootEnBlanco) {
    Aviso "root NO tiene contrasena. Vamos a ponerle una."
    $r1 = Read-Host "Nueva contrasena de root" -AsSecureString
    $r2 = Read-Host "Repite la contrasena de root" -AsSecureString
    $p1 = Texto-Plano $r1
    if ($p1 -ne (Texto-Plano $r2) -or $p1.Length -lt 8) {
        Falla "No coinciden o tienen menos de 8 caracteres. Vuelve a ejecutar el script."; exit 1
    }
    $p1e = $p1.Replace("'", "''")
    & $mariadb -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$p1e'; FLUSH PRIVILEGES;"
    $rootPass = $p1
    Ok "Contrasena de root establecida. ANOTALA en un lugar privado."
} else {
    $r = Read-Host "root ya tiene contrasena. Escribela" -AsSecureString
    $rootPass = Texto-Plano $r
}

$env:MYSQL_PWD = $rootPass
& $mariadb -u root -e "SELECT 1" *> $null
if ($LASTEXITCODE -ne 0) { Falla "La contrasena de root no es correcta."; $env:MYSQL_PWD = ""; exit 1 }

$u1 = Read-Host "Contrasena para el usuario 'invernadero' (min. 8 caracteres)" -AsSecureString
$up = Texto-Plano $u1
if ($up.Length -lt 8) { Falla "Demasiado corta."; $env:MYSQL_PWD = ""; exit 1 }
$upe = $up.Replace("'", "''")

$sql = @"
CREATE DATABASE IF NOT EXISTS monitor_invernadero CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'invernadero'@'localhost' IDENTIFIED BY '$upe';
ALTER USER 'invernadero'@'localhost' IDENTIFIED BY '$upe';
GRANT ALL PRIVILEGES ON monitor_invernadero.* TO 'invernadero'@'localhost';
FLUSH PRIVILEGES;
"@
$sql | & $mariadb -u root
if ($LASTEXITCODE -eq 0) { Ok "Base 'monitor_invernadero' y usuario 'invernadero' listos" }
else { Falla "No se pudo crear la base o el usuario." }
$env:MYSQL_PWD = ""

# ---------- 5. Firewall ----------
Paso "5. Firewall (puerto 8000, solo redes privadas)"
if (-not (Get-NetFirewallRule -DisplayName "AetherSprout PHP 8000" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "AetherSprout PHP 8000" -Direction Inbound -Protocol TCP `
        -LocalPort 8000 -Profile Private -Action Allow | Out-Null
    Ok "Regla creada"
} else { Ok "La regla ya existia" }

# ---------- 6. Repositorio (opcional) ----------
Paso "6. Repositorio"
$resp = Read-Host "Clonar AetherSprout en C:\proyectos? (s/n)"
if ($resp -eq 's') {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Aviso "Git aun no se reconoce en esta ventana. Abre una terminal nueva y clona a mano."
    } else {
        New-Item -ItemType Directory -Force -Path "C:\proyectos" | Out-Null
        Set-Location "C:\proyectos"
        if (-not (Test-Path "C:\proyectos\AetherSprout")) {
            git clone https://github.com/FernandoF00G/AetherSprout.git
        } else { Ok "La carpeta AetherSprout ya existe" }
        if (Test-Path "C:\proyectos\AetherSprout") {
            Set-Location "C:\proyectos\AetherSprout"
            $n = Read-Host "Tu nombre completo para los commits"
            $e = Read-Host "El correo de TU cuenta de GitHub"
            git config user.name  "$n"
            git config user.email "$e"
            Ok "Identidad fijada SOLO en este repositorio:"
            git config --list --local | Select-String "user\."
        }
    }
}

# ---------- Resumen ----------
Paso "Resumen"
Write-Host "Abre una terminal NUEVA (sin administrador) y verifica:"
Write-Host "  git --version"
Write-Host "  php -v"
Write-Host "  php -m | findstr mysql      (debe mostrar mysqli y pdo_mysql)"
Write-Host "  mariadb --version"
Write-Host "  Get-Service MariaDB         (Running)"
Write-Host ""
Write-Host "Pendiente a mano: extension 'Espressif IDF' en VS Code (version 5.3.x)." -ForegroundColor Yellow
