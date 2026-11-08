<?php
require __DIR__ . '/../../config/conexion.php';

header('Content-Type: application/json; charset=utf-8');

// Atraso maximo aceptado: 48 horas, en segundos (RF09)
const MAX_ATRASO_S = 172800;

// Rango provisional del oxigeno: la unidad esta por confirmar con el responsable
const OXIGENO_MIN = 0;
const OXIGENO_MAX = 100;

// Franjas de 4 horas, igual que en registros.php
const FRANJAS = [
    ['00:00', '04:00'], ['04:00', '08:00'], ['08:00', '12:00'],
    ['12:00', '16:00'], ['16:00', '20:00'], ['20:00', '24:00'],
];

function responder(int $codigo, array $cuerpo): void
{
    http_response_code($codigo);
    echo json_encode($cuerpo);
    exit;
}

// Valida un decimal positivo con punto decimal dentro de [$min, $max]
function validar_decimal(array $datos, string $campo, float $min, float $max, array &$errores): void
{
    if (!isset($datos[$campo]) || $datos[$campo] === '') {
        $errores[$campo] = 'falta el campo';
    } elseif (!is_string($datos[$campo])
              || !preg_match('/^\d+(\.\d+)?$/', $datos[$campo])) {
        $errores[$campo] = 'debe ser un numero positivo con punto decimal';
    } elseif ((float)$datos[$campo] < $min || (float)$datos[$campo] > $max) {
        $errores[$campo] = "debe estar entre $min y $max";
    }
}

// Campos opcionales comunes: id_origen y segundos_atraso
function validar_comunes(array $datos): array
{
    $errores = [];

    if (isset($datos['id_origen']) && $datos['id_origen'] !== '') {
        if (!is_string($datos['id_origen'])
            || !preg_match('/^[0-9a-z]{4,12}-[0-9]{1,10}$/', $datos['id_origen'])) {
            $errores['id_origen'] = 'formato invalido (ejemplo: a1b2c3d4-17)';
        }
    }

    if (isset($datos['segundos_atraso']) && $datos['segundos_atraso'] !== '') {
        if (!is_string($datos['segundos_atraso'])
            || !preg_match('/^\d{1,6}$/', $datos['segundos_atraso'])) {
            $errores['segundos_atraso'] = 'debe ser un entero de 0 a ' . MAX_ATRASO_S;
        } elseif ((int)$datos['segundos_atraso'] > MAX_ATRASO_S) {
            $errores['segundos_atraso'] = 'no puede pasar de ' . MAX_ATRASO_S . ' (48 horas)';
        }
    }

    return $errores;
}

// Reglas de la Seccion 4. Devuelve un arreglo de errores (vacio = todo valido).
function validar_lectura(array $datos): array
{
    $errores = [];

    $decimales = [
        'humedad'     => [0, 100],
        'temperatura' => [0, 55],
        'ph'          => [0, 14],
    ];
    foreach ($decimales as $campo => [$min, $max]) {
        validar_decimal($datos, $campo, $min, $max, $errores);
    }

    if (!isset($datos['ce']) || $datos['ce'] === '') {
        $errores['ce'] = 'falta el campo';
    } elseif (!is_string($datos['ce']) || !preg_match('/^\d{1,9}$/', $datos['ce'])) {
        $errores['ce'] = 'debe ser un entero de 0 a 999999999';
    }

    return $errores + validar_comunes($datos);
}

function validar_oxigeno(array $datos): array
{
    $errores = [];
    validar_decimal($datos, 'oxigeno', OXIGENO_MIN, OXIGENO_MAX, $errores);
    return $errores + validar_comunes($datos);
}

// Valores opcionales ya validados: id_origen (o null) y atraso en segundos
function datos_comunes(array $datos): array
{
    $id_origen = (isset($datos['id_origen']) && $datos['id_origen'] !== '')
        ? $datos['id_origen'] : null;
    $atraso = (isset($datos['segundos_atraso']) && $datos['segundos_atraso'] !== '')
        ? (int) $datos['segundos_atraso'] : 0;
    return [$id_origen, $atraso];
}

function es_duplicado(PDOException $e): bool
{
    return isset($e->errorInfo[1]) && (int) $e->errorInfo[1] === 1062;
}

// ---------- POST: guardar una lectura del ESP32 o un registro de oxigeno ----------

function guardar_lectura(array $datos): void
{
    $errores = validar_lectura($datos);
    if ($errores) {
        responder(400, ['error' => 'Lectura invalida', 'detalle' => $errores]);
    }
    [$id_origen, $atraso] = datos_comunes($datos);

    try {
        $pdo = obtener_conexion();

        // La fecha no se recibe: es la del servidor menos el atraso (0 si llego al instante)
        $insertar = $pdo->prepare(
            'INSERT INTO lectura
               (fecha_hora, humedad, temperatura, ph, ce, id_origen, atraso_s)
             VALUES
               (DATE_SUB(NOW(), INTERVAL :atraso SECOND),
                :humedad, :temperatura, :ph, :ce, :id_origen, :atraso_s)'
        );
        $insertar->bindValue(':atraso', $atraso, PDO::PARAM_INT);
        $insertar->bindValue(':humedad', $datos['humedad']);
        $insertar->bindValue(':temperatura', $datos['temperatura']);
        $insertar->bindValue(':ph', $datos['ph']);
        $insertar->bindValue(':ce', $datos['ce']);
        $insertar->bindValue(':id_origen', $id_origen,
            $id_origen === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $insertar->bindValue(':atraso_s', $atraso, PDO::PARAM_INT);
        $insertar->execute();

        $id = (int) $pdo->lastInsertId();
        $consulta = $pdo->prepare('SELECT fecha_hora FROM lectura WHERE id = :id');
        $consulta->execute([':id' => $id]);

        responder(201, [
            'guardada'   => true,
            'id'         => $id,
            'fecha_hora' => $consulta->fetchColumn(),
        ]);
    } catch (PDOException $e) {
        if (es_duplicado($e)) {
            // Ya estaba guardada: no es un error, el emisor puede olvidarla
            responder(200, ['guardada' => true, 'duplicada' => true, 'id_origen' => $id_origen]);
        }
        error_log('Error al guardar lectura: ' . $e->getMessage());
        responder(500, ['error' => 'No se pudo guardar la lectura']);
    }
}

function guardar_oxigeno(array $datos): void
{
    $errores = validar_oxigeno($datos);
    if ($errores) {
        responder(400, ['error' => 'Registro invalido', 'detalle' => $errores]);
    }
    [$id_origen, $atraso] = datos_comunes($datos);

    try {
        $pdo = obtener_conexion();

        $insertar = $pdo->prepare(
            'INSERT INTO lectura_oxigeno (fecha_hora, oxigeno, id_origen, atraso_s)
             VALUES (DATE_SUB(NOW(), INTERVAL :atraso SECOND), :oxigeno, :id_origen, :atraso_s)'
        );
        $insertar->bindValue(':atraso', $atraso, PDO::PARAM_INT);
        $insertar->bindValue(':oxigeno', $datos['oxigeno']);
        $insertar->bindValue(':id_origen', $id_origen,
            $id_origen === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
        $insertar->bindValue(':atraso_s', $atraso, PDO::PARAM_INT);
        $insertar->execute();

        $id = (int) $pdo->lastInsertId();
        $consulta = $pdo->prepare('SELECT fecha_hora FROM lectura_oxigeno WHERE id = :id');
        $consulta->execute([':id' => $id]);

        responder(201, [
            'guardada'   => true,
            'id'         => $id,
            'fecha_hora' => $consulta->fetchColumn(),
        ]);
    } catch (PDOException $e) {
        if (es_duplicado($e)) {
            responder(200, ['guardada' => true, 'duplicada' => true, 'id_origen' => $id_origen]);
        }
        error_log('Error al guardar oxigeno: ' . $e->getMessage());
        responder(500, ['error' => 'No se pudo guardar el registro de oxigeno']);
    }
}

// ---------- GET: ultima lectura y registros por fecha ----------

function consultar_ultima(): void
{
    try {
        $pdo = obtener_conexion();

        $lectura = $pdo->query(
            'SELECT fecha_hora, humedad, temperatura, ph, ce
             FROM lectura ORDER BY fecha_hora DESC, id DESC LIMIT 1'
        )->fetch();
        $oxigeno = $pdo->query(
            'SELECT fecha_hora, oxigeno
             FROM lectura_oxigeno ORDER BY fecha_hora DESC, id DESC LIMIT 1'
        )->fetch();

        responder(200, [
            'lectura' => $lectura ? [
                'fecha_hora'  => $lectura['fecha_hora'],
                'humedad'     => (float) $lectura['humedad'],
                'temperatura' => (float) $lectura['temperatura'],
                'ph'          => (float) $lectura['ph'],
                'ce'          => (int) $lectura['ce'],
            ] : null,
            'oxigeno' => $oxigeno ? [
                'fecha_hora' => $oxigeno['fecha_hora'],
                'oxigeno'    => (float) $oxigeno['oxigeno'],
            ] : null,
        ]);
    } catch (PDOException $e) {
        error_log('Error al consultar la ultima lectura: ' . $e->getMessage());
        responder(500, ['error' => 'No se pudo consultar la base de datos']);
    }
}

function consultar_registros($fecha): void
{
    $dia = is_string($fecha) ? DateTime::createFromFormat('!Y-m-d', $fecha) : false;
    if (!$dia || $dia->format('Y-m-d') !== $fecha) {
        responder(400, ['error' => 'Fecha invalida', 'detalle' => 'use el formato AAAA-MM-DD']);
    }
    $inicio = $dia->format('Y-m-d H:i:s');
    $fin = $dia->modify('+1 day')->format('Y-m-d H:i:s');

    try {
        $pdo = obtener_conexion();

        $franjas = [];
        foreach (FRANJAS as [$desde, $hasta]) {
            $franjas[] = ['desde' => $desde, 'hasta' => $hasta, 'lecturas' => [], 'oxigeno' => []];
        }

        $lecturas = $pdo->prepare(
            'SELECT fecha_hora, humedad, temperatura, ph, ce
             FROM lectura
             WHERE fecha_hora >= :inicio AND fecha_hora < :fin
             ORDER BY fecha_hora ASC, id ASC'
        );
        $lecturas->execute([':inicio' => $inicio, ':fin' => $fin]);
        $total = 0;
        foreach ($lecturas as $f) {
            $hora = (int) substr($f['fecha_hora'], 11, 2);
            $franjas[intdiv($hora, 4)]['lecturas'][] = [
                'hora'        => substr($f['fecha_hora'], 11, 8),
                'humedad'     => (float) $f['humedad'],
                'temperatura' => (float) $f['temperatura'],
                'ph'          => (float) $f['ph'],
                'ce'          => (int) $f['ce'],
            ];
            $total++;
        }

        $oxigenos = $pdo->prepare(
            'SELECT fecha_hora, oxigeno
             FROM lectura_oxigeno
             WHERE fecha_hora >= :inicio AND fecha_hora < :fin
             ORDER BY fecha_hora ASC, id ASC'
        );
        $oxigenos->execute([':inicio' => $inicio, ':fin' => $fin]);
        $total_oxigeno = 0;
        foreach ($oxigenos as $o) {
            $hora = (int) substr($o['fecha_hora'], 11, 2);
            $franjas[intdiv($hora, 4)]['oxigeno'][] = [
                'hora'    => substr($o['fecha_hora'], 11, 8),
                'oxigeno' => (float) $o['oxigeno'],
            ];
            $total_oxigeno++;
        }

        responder(200, [
            'fecha'         => $fecha,
            'total'         => $total,
            'total_oxigeno' => $total_oxigeno,
            'franjas'       => $franjas,
        ]);
    } catch (PDOException $e) {
        error_log('Error al consultar registros: ' . $e->getMessage());
        responder(500, ['error' => 'No se pudo consultar la base de datos']);
    }
}

// ---------- Enrutado por metodo ----------

$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'POST') {
    $tipo = $_POST['tipo_registro'] ?? '';
    if ($tipo === '') {
        guardar_lectura($_POST);
    } elseif ($tipo === 'oxigeno_manual') {
        guardar_oxigeno($_POST);
    } else {
        responder(400, ['error' => 'tipo_registro desconocido']);
    }
} elseif ($metodo === 'GET') {
    $accion = $_GET['accion'] ?? 'ultima';
    if ($accion === 'ultima') {
        consultar_ultima();
    } elseif ($accion === 'registros') {
        consultar_registros($_GET['fecha'] ?? null);
    } else {
        responder(400, ['error' => 'accion desconocida']);
    }
} else {
    header('Allow: GET, POST');
    responder(405, ['error' => 'Use el metodo GET o POST']);
}
