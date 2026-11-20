# registrar-dispositivo.ps1
# Da de alta una placa ESP32 (identificador + sitio) y le genera una clave.
# Si la placa ya existe, ofrece generarle una clave nueva (por si se perdio).
# La clave se muestra UNA sola vez; en la base solo se guarda su hash.
# Uso:  powershell -ExecutionPolicy Bypass -File .\scripts\registrar-dispositivo.ps1
param(
    [string]$Usuario = 'invernadero',
    [string]$Base    = 'monitor_invernadero'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_comun.ps1"

Paso "Registrar dispositivo en '$Base'"

$mariadb = Buscar-Exe "mariadb"
if (-not $mariadb) { Falla "No encuentro mariadb.exe. Ejecuta primero scripts\instalar.ps1"; exit 1 }
if (-not (Get-Command php -ErrorAction SilentlyContinue)) { Falla "No encuentro php en el PATH."; exit 1 }

# Ejecuta SQL enviandolo por la entrada estandar (evita problemas con comillas)
function Ejecutar-SQL([string]$sql, [switch]$Tabla) {
    if ($Tabla) { $r = $sql | & $mariadb -u $Usuario $Base -N -B }
    else        { $r = $sql | & $mariadb -u $Usuario $Base }
    if ($LASTEXITCODE -ne 0) { throw "MariaDB devolvio un error (codigo $LASTEXITCODE)." }
    return $r
}

$pidio = Pedir-PasswordBD $Usuario
try {
    Ejecutar-SQL "SELECT 1" -Tabla | Out-Null
    Ok "Conexion correcta"

    # ---- 1) Identificador ----
    $ident = (Read-Host "Identificador de la placa (minusculas, numeros y guiones; ej. invernadero1)").Trim()
    if ($ident -cnotmatch '^[a-z0-9-]{3,32}$') {
        Falla "Identificador invalido: solo minusculas, numeros y guiones, de 3 a 32 caracteres."
        exit 1
    }

    $existente = @(Ejecutar-SQL "SELECT id, activo FROM dispositivos WHERE identificador = '$ident'" -Tabla)
    $esNuevo = ($existente.Count -eq 0 -or [string]::IsNullOrWhiteSpace($existente[0]))

    if (-not $esNuevo) {
        $idDisp = ($existente[0] -split "`t")[0]
        Aviso "La placa '$ident' ya existe (id $idDisp)."
        $resp = Read-Host "Generar una CLAVE NUEVA para ella? La anterior dejara de servir (s/n)"
        if ($resp -ne 's') { Write-Host "Sin cambios."; exit 0 }
    } else {
        # ---- 2) Sitio ----
        Write-Host ""
        Write-Host "Sitios disponibles:"
        $sitios = @(Ejecutar-SQL "SELECT id, nombre FROM ubicaciones WHERE activo = 1 ORDER BY id" -Tabla)
        $ids = @()
        foreach ($s in $sitios) {
            $c = $s -split "`t"
            Write-Host ("  {0}) {1}" -f $c[0], $c[1])
            $ids += $c[0]
        }
        $idUbic = (Read-Host "Numero del sitio donde estara la placa").Trim()
        if ($ids -notcontains $idUbic) { Falla "Ese numero no esta en la lista."; exit 1 }
    }

    # ---- 3) Clave aleatoria: 16 bytes = 32 caracteres hexadecimales ----
    $bytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    $clave = -join ($bytes | ForEach-Object { $_.ToString('x2') })

    # Hash con PHP (el mismo password_verify lo comprobara en la API).
    # La clave viaja por una variable de entorno, no por la linea de comandos.
    $env:AS_CLAVE_DISP = $clave
    try {
        $hash = (& php -r "echo password_hash(getenv('AS_CLAVE_DISP'), PASSWORD_DEFAULT);").Trim()
    } finally {
        Remove-Item Env:AS_CLAVE_DISP -ErrorAction SilentlyContinue
    }
    if ($hash -notmatch '^\$2y\$') { Falla "PHP no genero el hash correctamente."; exit 1 }

    # ---- 4) Guardar + bitacora (en la misma conexion, por LAST_INSERT_ID) ----
    if ($esNuevo) {
        $sql = @'
INSERT INTO dispositivos (identificador, ubicacion_id, clave_hash) VALUES ('{0}', {1}, '{2}');
INSERT INTO bitacora (accion, objeto, objeto_id, detalle)
SELECT 'registrar_dispositivo', 'dispositivo', LAST_INSERT_ID(),
       CONCAT('Dispositivo {0} registrado en ', nombre, ' (por script)')
FROM ubicaciones WHERE id = {1};
'@ -f $ident, $idUbic, $hash
    } else {
        $sql = @'
UPDATE dispositivos SET clave_hash = '{1}' WHERE id = {0};
INSERT INTO bitacora (accion, objeto, objeto_id, detalle)
VALUES ('cambiar_clave_dispositivo', 'dispositivo', {0}, 'Clave nueva para el dispositivo {2} (por script)');
'@ -f $idDisp, $hash, $ident
    }
    Ejecutar-SQL $sql | Out-Null
    Ok "Dispositivo '$ident' guardado."

    # ---- 5) Mostrar la clave una sola vez ----
    Write-Host ""
    Write-Host "================ COPIA ESTO AHORA ================" -ForegroundColor Yellow
    Write-Host "En firmware\main\config_local.h (NUNCA en el repositorio):"
    Write-Host ""
    Write-Host ("#define DISPOSITIVO_ID     ""{0}""" -f $ident)
    Write-Host ("#define DISPOSITIVO_CLAVE  ""{0}""" -f $clave)
    Write-Host ""
    Write-Host "La clave no se guarda en ningun lado: si la pierdes, vuelve a"
    Write-Host "ejecutar este script con el mismo identificador para generar otra."
    Write-Host "==================================================" -ForegroundColor Yellow
}
catch {
    Falla $_.Exception.Message
    exit 1
}
finally {
    $clave = $null
    if ($pidio) { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}
