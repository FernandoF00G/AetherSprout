<?php
require __DIR__ . '/../../config/conexion.php';

header('Content-Type: application/json; charset=utf-8');

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
        if (!isset($datos[$campo]) || $datos[$campo] === '') {
            $errores[$campo] = 'falta el campo';
        } elseif (!is_string($datos[$campo])
                  || !preg_match('/^\d+(\.\d+)?$/', $datos[$campo])) {
            $errores[$campo] = 'debe ser un numero positivo con punto decimal';
        } elseif ((float)$datos[$campo] < $min || (float)$datos[$campo] > $max) {
            $errores[$campo] = "debe estar entre $min y $max";
        }
    }

    if (!isset($datos['ce']) || $datos['ce'] === '') {
        $errores['ce'] = 'falta el campo';
    } elseif (!is_string($datos['ce']) || !preg_match('/^\d{1,9}$/', $datos['ce'])) {
        $errores['ce'] = 'debe ser un entero de 0 a 999999999';
    }

    return $errores;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    echo json_encode(['error' => 'Use el metodo POST']);
    exit;
}

$errores = validar_lectura($_POST);
if ($errores) {
    http_response_code(400);
    echo json_encode(['error' => 'Lectura invalida', 'detalle' => $errores]);
    exit;
}

try {
    $pdo = obtener_conexion();

    // fecha_hora no se envia: la asigna MariaDB (DEFAULT CURRENT_TIMESTAMP)
    $insertar = $pdo->prepare(
        'INSERT INTO lectura (humedad, temperatura, ph, ce)
         VALUES (:humedad, :temperatura, :ph, :ce)'
    );
    $insertar->execute([
        ':humedad'     => $_POST['humedad'],
        ':temperatura' => $_POST['temperatura'],
        ':ph'          => $_POST['ph'],
        ':ce'          => $_POST['ce'],
    ]);

    $id = (int) $pdo->lastInsertId();
    $consulta = $pdo->prepare('SELECT fecha_hora FROM lectura WHERE id = :id');
    $consulta->execute([':id' => $id]);

    http_response_code(201);
    echo json_encode([
        'guardada'   => true,
        'id'         => $id,
        'fecha_hora' => $consulta->fetchColumn(),
    ]);
} catch (PDOException $e) {
    error_log('Error al guardar lectura: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => 'No se pudo guardar la lectura']);
}