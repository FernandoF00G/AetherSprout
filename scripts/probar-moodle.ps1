# probar-moodle.ps1
# Prueba SOLO DE LECTURA contra el Moodle de la universidad, para ver:
#   1) si el PHP de esta computadora puede conectarse por HTTPS,
#   2) si el login devuelve un token,
#   3) que funciones del servicio web estan permitidas,
#   4) en que cursos esta la cuenta y con que rol.
# No guarda la contrasena ni el token, y no los imprime.
# Uso (con TU PROPIA cuenta):  .\scripts\probar-moodle.ps1
$ErrorActionPreference = 'Stop'

if (-not (Get-Command php -ErrorAction SilentlyContinue)) {
    Write-Host "[X] No encuentro php en el PATH." -ForegroundColor Red
    exit 1
}

$codigoPhp = @'
<?php
$base = rtrim(getenv('MOODLE_BASE') ?: 'https://pregrados.cunorte.udg.mx', '/');
$user = getenv('MOODLE_USER');
$pass = getenv('MOODLE_PASS');

function linea($t = '') { echo $t . PHP_EOL; }

linea("PHP " . PHP_VERSION . " | php.ini: " . (php_ini_loaded_file() ?: 'NINGUNO'));
if (!extension_loaded('curl')) {
    linea("[X] La extension curl NO esta activa. En php.ini quita el ';' de la linea extension=curl y vuelve a probar.");
    exit(1);
}
linea("curl.cainfo = " . (ini_get('curl.cainfo') ?: '(vacio)') . " | openssl.cafile = " . (ini_get('openssl.cafile') ?: '(vacio)'));

function http($url, $campos)
{
    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL            => $url,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => http_build_query($campos),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 15,
    ]);
    $r = curl_exec($ch);
    $res = [$r, curl_getinfo($ch, CURLINFO_HTTP_CODE), curl_error($ch), curl_errno($ch)];
    curl_close($ch);
    return $res;
}

function ws($base, $token, $fn, $params = [])
{
    [$r, $code, $err, $errno] = http($base . '/webservice/rest/server.php',
        ['wstoken' => $token, 'wsfunction' => $fn, 'moodlewsrestformat' => 'json'] + $params);
    if ($r === false) { return ['__fallo' => "curl $errno: $err"]; }
    $d = json_decode($r, true);
    return is_array($d) ? $d : ['__fallo' => "respuesta no JSON (HTTP $code)"];
}

function motivo($d)
{
    if (isset($d['__fallo'])) { return $d['__fallo']; }
    if (isset($d['errorcode'])) { return 'errorcode=' . $d['errorcode']; }
    return null;
}

// ---- 1) Login ----
linea();
linea("== 1) Login (login/token.php, servicio moodle_mobile_app) ==");
[$r, $code, $err, $errno] = http($base . '/login/token.php',
    ['service' => 'moodle_mobile_app', 'username' => $user, 'password' => $pass]);
if ($r === false) {
    linea("[X] No se pudo conectar: curl $errno: $err");
    if ($errno === 60 || $errno === 77) {
        linea("    Es el caso tipico de Windows: a PHP le falta el archivo de certificados (cacert.pem).");
    }
    exit(1);
}
linea("HTTP $code");
$d = json_decode($r, true);
if (!is_array($d)) { linea("[X] La respuesta no es JSON."); exit(1); }
if (isset($d['error'])) {
    linea("[X] Moodle rechazo el login. errorcode=" . ($d['errorcode'] ?? '?'));
    exit(1);
}
if (!isset($d['token'])) { linea("[X] La respuesta no trae token."); exit(1); }
$token = $d['token'];
linea("[OK] Token recibido (longitud " . strlen($token) . ", no se muestra).");

// ---- 2) Datos del sitio y funciones permitidas ----
linea();
linea("== 2) Sitio y funciones permitidas para este token ==");
$s = ws($base, $token, 'core_webservice_get_site_info');
if ($m = motivo($s)) { linea("[X] No se pudo leer site_info: $m"); exit(1); }
$uid = $s['userid'] ?? null;
linea("Moodle: " . ($s['release'] ?? '?') . " | userid: $uid | cuenta: " . substr((string)$user, 0, 2) . "*** | admin del sitio: " . (!empty($s['userissiteadmin']) ? 'si' : 'no'));
$permitidas = array_column($s['functions'] ?? [], 'name');
linea("Funciones permitidas en total: " . count($permitidas));
foreach (['core_enrol_get_users_courses', 'core_user_get_course_user_profiles', 'core_enrol_get_enrolled_users', 'core_user_get_users_by_field'] as $f) {
    linea(str_pad($f, 38) . (in_array($f, $permitidas, true) ? 'permitida' : 'NO permitida'));
}

// ---- 3) Cursos ----
linea();
linea("== 3) Cursos de la cuenta ==");
$cursos = ws($base, $token, 'core_enrol_get_users_courses', ['userid' => $uid]);
if ($m = motivo($cursos)) { linea("[X] No se pudieron leer los cursos: $m"); exit(0); }
linea("Cursos encontrados: " . count($cursos));
$cursos = array_slice($cursos, 0, 10);
foreach ($cursos as $c) {
    linea("  id " . ($c['id'] ?? '?') . " | " . ($c['shortname'] ?? '?') . " | " . ($c['fullname'] ?? '?'));
}

// ---- 4) Rol en cada curso ----
linea();
linea("== 4) Rol de la cuenta en cada curso ==");
foreach ($cursos as $c) {
    $p = ws($base, $token, 'core_user_get_course_user_profiles',
        ['userlist' => [['userid' => $uid, 'courseid' => $c['id']]]]);
    if ($m = motivo($p)) { linea("  curso " . $c['id'] . ": [no disponible] $m"); continue; }
    $roles = [];
    foreach (($p[0]['roles'] ?? []) as $ro) { $roles[] = $ro['shortname'] ?? ($ro['name'] ?? '?'); }
    linea("  curso " . $c['id'] . ": " . ($roles ? implode(', ', $roles) : '(sin roles en la respuesta)'));
}

// ---- 5) Que roles existen en cada curso (solo conteos, sin nombres) ----
linea();
linea("== 5) Roles presentes en cada curso (solo conteos; no se muestran nombres) ==");
foreach ($cursos as $c) {
    $u = ws($base, $token, 'core_enrol_get_enrolled_users', ['courseid' => $c['id']]);
    if ($m = motivo($u)) { linea("  curso " . $c['id'] . ": [no disponible] $m"); continue; }
    $cuenta = [];
    foreach ($u as $persona) {
        foreach (($persona['roles'] ?? []) as $ro) {
            $k = $ro['shortname'] ?? '?';
            $cuenta[$k] = ($cuenta[$k] ?? 0) + 1;
        }
    }
    ksort($cuenta);
    $txt = [];
    foreach ($cuenta as $k => $n) { $txt[] = "$k=$n"; }
    linea("  curso " . $c['id'] . ": " . ($txt ? implode(', ', $txt) : '(sin roles en la respuesta)'));
}

linea();
linea("Listo. Esta salida no contiene contrasena ni token.");
'@

$u = Read-Host "Usuario de Moodle (tu propia cuenta)"
$sec = Read-Host "Contrasena (no se muestra)" -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$env:MOODLE_USER = $u
$env:MOODLE_PASS = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$tmp = Join-Path $env:TEMP 'probar-moodle.php'
[System.IO.File]::WriteAllText($tmp, $codigoPhp, (New-Object System.Text.UTF8Encoding($false)))
try {
    & php $tmp
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item Env:MOODLE_USER, Env:MOODLE_PASS -ErrorAction SilentlyContinue
}
