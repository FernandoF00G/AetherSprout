<?php
require __DIR__ . '/../../config/conexion.php';

header('Content-Type: application/json; charset=utf-8');

try {
    $pdo = obtener_conexion();
    $hora_mariadb = $pdo->query('SELECT NOW()')->fetchColumn();

    echo json_encode([
        'conexion'     => 'ok',
        'hora_php'     => date('Y-m-d H:i:s'),
        'hora_mariadb' => $hora_mariadb,
    ]);
} catch (PDOException $e) {
    error_log('Error de conexion: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => 'No se pudo conectar a la base de datos']);
}