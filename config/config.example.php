<?php
// Plantilla de configuracion. NO pongas contrasenas reales aqui.
// El script scripts/preparar-servidor.ps1 genera config/config.php
// (ese archivo SI lleva la contrasena y Git lo ignora).
return [
    'db_host'      => '127.0.0.1',
    'db_port'      => 3306,
    'db_name'      => 'monitor_invernadero',
    'db_user'      => 'invernadero',
    'db_pass'      => 'CAMBIAR',
    'zona_horaria' => 'America/Mexico_City',
];
