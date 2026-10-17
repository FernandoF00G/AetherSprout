# Funciones compartidas por los scripts de AetherSprout (archivo en ASCII).
# No se ejecuta solo: los otros scripts lo cargan con ". _comun.ps1".

$RaizRepo = Split-Path $PSScriptRoot -Parent

function Paso($t)  { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "[OK] $t" -ForegroundColor Green }
function Aviso($t) { Write-Host "[!]  $t" -ForegroundColor Yellow }
function Falla($t) { Write-Host "[X]  $t" -ForegroundColor Red }

function Buscar-Exe($nombre) {
    $cmd = Get-Command $nombre -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $dir = Get-ChildItem "C:\Program Files" -Directory -Filter "MariaDB*" -ErrorAction SilentlyContinue |
           Where-Object { Test-Path (Join-Path $_.FullName "bin\$nombre.exe") } |
           Sort-Object Name -Descending | Select-Object -First 1
    if ($dir) { return (Join-Path $dir.FullName "bin\$nombre.exe") }
    return $null
}

function Texto-Plano([System.Security.SecureString]$s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# Pide la contrasena del usuario de la base y la deja en MYSQL_PWD (solo en esta sesion).
# Devuelve $true si la pidio ella; $false si ya estaba puesta.
function Pedir-PasswordBD($usuario) {
    if ($env:MYSQL_PWD) { return $false }
    $s = Read-Host "Contrasena del usuario '$usuario' de MariaDB (de ESTA computadora)" -AsSecureString
    $env:MYSQL_PWD = Texto-Plano $s
    return $true
}
