<?php
// Devuelve una conexion PDO a MariaDB usando config/config.php
function obtener_conexion(): PDO
{
    $cfg = require __DIR__ . '/config.php';
    date_default_timezone_set($cfg['zona_horaria']);

    $dsn = "mysql:host={$cfg['db_host']};port={$cfg['db_port']};"
         . "dbname={$cfg['db_name']};charset=utf8mb4";

    return new PDO($dsn, $cfg['db_user'], $cfg['db_pass'], [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES   => false,
    ]);
}