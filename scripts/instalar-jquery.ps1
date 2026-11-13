# =====================================================================
# instalar-jquery.ps1 - Descarga jQuery 3.7.1 a public/assets/js/
# Se ejecuta UNA vez; el archivo queda en el repositorio, asi la red del
# invernadero nunca necesita internet para cargar la pagina.
#
# Uso (desde la raiz del repositorio):
#   .\scripts\instalar-jquery.ps1
#   .\scripts\instalar-jquery.ps1 -HashEsperado "sha256-..."
#
# El hash correcto se copia de https://releases.jquery.com/ (jQuery 3.7.1,
# minified, campo "integrity"). Con -HashEsperado el script borra el archivo
# si el hash no coincide. Sin ese parametro solo muestra el hash para que
# lo compares tu.
# (Archivo en ASCII a proposito, para evitar problemas de codificacion.)
# =====================================================================
param(
    [string]$HashEsperado = ""
)

. "$PSScriptRoot\_comun.ps1"

$ErrorActionPreference = 'Stop'
$version = "3.7.1"
$url     = "https://code.jquery.com/jquery-$version.min.js"
$destDir = Join-Path $RaizRepo "public\assets\js"
$destino = Join-Path $destDir "jquery-$version.min.js"

Paso "Instalar jQuery $version"

if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir | Out-Null
}

try {
    Write-Host "Descargando $url ..."
    Invoke-WebRequest -Uri $url -OutFile $destino -UseBasicParsing
} catch {
    Falla "No se pudo descargar: $($_.Exception.Message)"
    exit 1
}

# Hash en dos formatos: hexadecimal y el formato "sha256-..." de releases.jquery.com
$hex = (Get-FileHash -Path $destino -Algorithm SHA256).Hash.ToLower()
$sri = "sha256-" + [Convert]::ToBase64String(
           [byte[]] ($hex -split '(..)' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) }))
$bytes = (Get-Item $destino).Length

Ok "Guardado en $destino ($bytes bytes)"
Write-Host "SHA256 (hex):     $hex"
Write-Host "SHA256 (formato releases.jquery.com): $sri"

if ($HashEsperado -ne "") {
    if ($HashEsperado.Trim() -eq $sri) {
        Ok "El hash coincide con el esperado"
    } else {
        Remove-Item $destino -Force
        Falla "El hash NO coincide. Se borro el archivo descargado."
        Falla "Esperado: $HashEsperado"
        exit 1
    }
} else {
    Aviso "Compara el hash de arriba con el de https://releases.jquery.com/ (jQuery $version, minified)."
    Aviso "O vuelve a ejecutar con -HashEsperado ""sha256-..."" para que se verifique solo."
}

# Ninguna pagina debe cargar recursos de internet
$externos = Get-ChildItem (Join-Path $RaizRepo "public") -Include *.php,*.html -Recurse |
            Select-String -Pattern '(src|href)\s*=\s*["'']https?://' -ErrorAction SilentlyContinue
if ($externos) {
    Aviso "Hay enlaces externos en las paginas:"
    $externos | ForEach-Object { Write-Host "   $($_.Path):$($_.LineNumber)" }
} else {
    Ok "Ninguna pagina tiene enlaces http:// o https:// externos"
}
