<?php
require __DIR__ . '/../config/conexion.php';

function h($t): string
{
    return htmlspecialchars((string) $t, ENT_QUOTES, 'UTF-8');
}

$lectura = null;
$error = null;
try {
    $pdo = obtener_conexion();
    $lectura = $pdo->query(
        'SELECT fecha_hora, humedad, temperatura, ph, ce
         FROM lectura ORDER BY fecha_hora DESC, id DESC LIMIT 1'
    )->fetch(); // false si la tabla esta vacia
} catch (PDOException $e) {
    error_log('Error al consultar la ultima lectura: ' . $e->getMessage());
    $error = 'No se pudo consultar la base de datos.';
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Monitor del invernadero</title>
  <link href="/assets/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4" style="max-width: 600px;">
  <h1 class="h3 mb-3">Monitor del invernadero</h1>

  <?php if ($error): ?>
    <div class="alert alert-danger"><?= h($error) ?></div>
  <?php elseif (!$lectura): ?>
    <div class="alert alert-info">Aún no hay lecturas.</div>
  <?php else: ?>
    <p class="text-muted mb-3">
      Última lectura:
      <strong><?= h(date('d/m/Y H:i:s', strtotime($lectura['fecha_hora']))) ?></strong>
    </p>
    <div class="row g-3 mb-4">
      <div class="col-6">
        <div class="card text-center h-100"><div class="card-body">
          <div class="text-muted">Humedad</div>
          <div class="fs-2"><?= h(number_format((float) $lectura['humedad'], 1, '.', '')) ?> %</div>
        </div></div>
      </div>
      <div class="col-6">
        <div class="card text-center h-100"><div class="card-body">
          <div class="text-muted">Temperatura</div>
          <div class="fs-2"><?= h(number_format((float) $lectura['temperatura'], 1, '.', '')) ?> °C</div>
        </div></div>
      </div>
      <div class="col-6">
        <div class="card text-center h-100"><div class="card-body">
          <div class="text-muted">pH</div>
          <div class="fs-2"><?= h(number_format((float) $lectura['ph'], 1, '.', '')) ?></div>
        </div></div>
      </div>
      <div class="col-6">
        <div class="card text-center h-100"><div class="card-body">
          <div class="text-muted">CE</div>
          <div class="fs-2"><?= h((int) $lectura['ce']) ?></div>
          <div class="small text-muted">µS/cm</div>
        </div></div>
      </div>
    </div>
  <?php endif; ?>

  <a class="btn btn-success w-100" href="/registros.php">Consultar registros</a>
</div>
</body>
</html>