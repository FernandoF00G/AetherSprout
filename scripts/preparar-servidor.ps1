# preparar-servidor.ps1
# Deja lista la computadora que hara de SERVIDOR en las pruebas y la demostracion:
#   1) servicio MariaDB en ejecucion
#   2) git pull
#   3) config\config.php con la contrasena de ESTA computadora (Git lo ignora)
#   4) base de datos al dia (llama a actualizar-bd.ps1)
#   5) regla de firewall del puerto 8000
#   6) muestra la IP que debe usar el ESP32
# Requisito previo en una computadora nueva: scripts\instalar.ps1
# Conviene ejecutarlo como administrador (para iniciar el servicio y el firewall).
param(
    [string]$Usuario = 'invernadero',
    [string]$Base    = 'monitor_invernadero'
)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\_comun.ps1"

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) { Aviso "No eres administrador: puede que no pueda iniciar el servicio ni abrir el firewall." }

# ---- 1. Servicio ----
Paso "1. Servicio MariaDB"
$svc = Get-CimInstance Win32_Service | Where-Object { $_.PathName -match "mariadbd" } | Select-Object -First 1
if (-not $svc) { Falla "No hay servicio de MariaDB. Ejecuta primero scripts\instalar.ps1 como administrador."; exit 1 }
if ((Get-Service $svc.Name).Status -ne 'Running') {
    Start-Service $svc.Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
if ((Get-Service $svc.Name).Status -eq 'Running') { Ok "Servicio $($svc.Name) en ejecucion" }
else { Falla "El servicio no esta corriendo. Abre PowerShell como administrador y repite."; exit 1 }

# ---- 2. Git ----
Paso "2. Ultimo codigo del repositorio"
if (Get-Command git -ErrorAction SilentlyContinue) { git -C $RaizRepo pull }
else { Aviso "Git no se reconoce; me salto el git pull." }

# ---- 3. config.php ----
Paso "3. config\config.php"
$pidio = Pedir-PasswordBD $Usuario
$cfg = Join-Path $RaizRepo "config\config.php"
if (Test-Path $cfg) {
    Ok "config.php ya existe (borralo si quieres regenerarlo)"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    $pwPhp = $env:MYSQL_PWD.Replace('\', '\\').Replace("'", "\'")
    $texto = @"
<?php
// Generado por scripts/preparar-servidor.ps1. NO se sube a Git.
return [
    'db_host'      => '127.0.0.1',
    'db_port'      => 3306,
    'db_name'      => '$Base',
    'db_user'      => '$Usuario',
    'db_pass'      => '$pwPhp',
    'zona_horaria' => 'America/Mexico_City',
];
"@
    # UTF-8 sin BOM, para que PHP no emita caracteres extra antes de <?php
    [IO.File]::WriteAllText($cfg, $texto, (New-Object Text.UTF8Encoding $false))
    Ok "Creado $cfg"
}

# ---- 4. Base de datos ----
Paso "4. Base de datos al dia"
& "$PSScriptRoot\actualizar-bd.ps1" -Usuario $Usuario -Base $Base -SinPull
if ($pidio) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }

# ---- 5. Firewall ----
Paso "5. Firewall (puerto 8000, red privada)"
if (Get-NetFirewallRule -DisplayName "AetherSprout PHP 8000" -ErrorAction SilentlyContinue) {
    Ok "La regla ya existe"
} elseif ($esAdmin) {
    New-NetFirewallRule -DisplayName "AetherSprout PHP 8000" -Direction Inbound -Protocol TCP `
        -LocalPort 8000 -Profile Private -Action Allow | Out-Null
    Ok "Regla creada"
} else { Aviso "Sin administrador no pude crear la regla del puerto 8000." }

# ---- 6. Red ----
Paso "6. IP para el ESP32"
$redes = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' }
if (-not $redes) { Aviso "No encontre una red activa con salida (revisa el WiFi/Ethernet)." }
foreach ($r in $redes) {
    $cat = (Get-NetConnectionProfile -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue).NetworkCategory
    Write-Host ("  {0}: {1}   (perfil de red: {2})" -f $r.InterfaceAlias, $r.IPv4Address.IPAddress, $cat)
    if ($cat -ne 'Private') {
        Aviso "  Esa red NO esta como 'Privada': la regla de firewall no aplicara y el ESP32 no podra llegar."
    }
}
Write-Host ""
Write-Host "Esa IP es la que Laura debe poner en la configuracion del ESP32," -ForegroundColor Yellow
Write-Host "con el puerto 8000. Debe ser la MISMA red WiFi de 2.4 GHz." -ForegroundColor Yellow
Write-Host ""
Write-Host "Cuando exista el codigo de la pagina, el servidor se inicia con:"
Write-Host "  cd $RaizRepo"
Write-Host "  php -S 0.0.0.0:8000 -t public     (la carpeta 'public' se define en la Seccion 5)"
