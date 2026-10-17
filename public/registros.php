<?php
require __DIR__ . '/../config/conexion.php';

function h($t): string
{
    return htmlspecialchars((string) $t, ENT_QUOTES, 'UTF-8');
}

$franjas = [
    ['00:00', '04:00'], ['04:00', '08:00'], ['08:00', '12:00'],
    ['12:00', '16:00'], ['16:00', '20:00'], ['20:00', '24:00'],
];

$pdo = null;
$error = null;
$aviso = null;
$por_franja = array_fill(0, 6, []);
$total = 0;
$consultar = false;

// obtener_conexion() tambien fija la zona horaria, por eso va antes de date()
try {
    $pdo = obtener_conexion();
} catch (PDOException $e) {
    error_log('Error de conexion: ' . $e->getMessage());
    $error = 'No se pudo conectar a la base de datos.';
}

$hoy = date('Y-m-d');
$fecha = $_GET['fecha'] ?? $hoy;
$dia = is_string($fecha) ? DateTime::createFromFormat('!Y-m-d', $fecha) : false;
if ($dia && $dia->format('Y-m-d') === $fecha) {
    $consultar = true;
} else {
    $aviso = 'La fecha no es válida. Elige otra.';
    $fecha = $hoy;
    $dia = DateTime::createFromFormat('!Y-m-d', $hoy);
}

if ($pdo && $consultar) {
    try {
        $inicio = $dia->format('Y-m-d') . ' 00:00:00';
        $fin = (clone $dia)->modify('+1 day')->format('Y-m-d') . ' 00:00:00';

        $consulta = $pdo->prepare(
            'SELECT fecha_hora, humedad, temperatura, ph, ce
             FROM lectura
             WHERE fecha_hora >= :inicio AND fecha_hora < :fin
             ORDER BY fecha_hora ASC, id ASC'
        );
        $consulta->execute([':inicio' => $inicio, ':fin' => $fin]);
        $filas = $consulta->fetchAll();

        foreach ($filas as $f) {
            $hora = (int) substr($f['fecha_hora'], 11, 2);
            $por_franja[intdiv($hora, 4)][] = $f;
        }
        $total = count($filas);
    } catch (PDOException $e) {
        error_log('Error al consultar registros: ' . $e->getMessage());
        $error = 'No se pudo consultar la base de datos.';
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Registros por fecha</title>
  <link href="/assets/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4" style="max-width: 600px;">
  <h1 class="h3 mb-3">Registros por fecha</h1>

  <form method="get" action="/registros.php" class="row g-2 mb-3">
    <div class="col-8">
      <label for="fecha" class="visually-hidden">Fecha</label>
      <input type="date" id="fecha" name="fecha" class="form-control"
             value="<?= h($fecha) ?>" required>
    </div>
    <div class="col-4">
      <button type="submit" class="btn btn-success w-100">Consultar</button>
    </div>
  </form>

  <?php if ($error): ?>
    <div class="alert alert-danger"><?= h($error) ?></div>
  <?php elseif ($aviso): ?>
    <div class="alert alert-warning"><?= h($aviso) ?></div>
  <?php elseif ($total === 0): ?>
    <div class="alert alert-info">Sin registros para esa fecha.</div>
  <?php else: ?>
    <p class="text-muted">
      <?= h($total) ?> lectura<?= $total === 1 ? '' : 's' ?> del
      <strong><?= h($dia->format('d/m/Y')) ?></strong>
    </p>

    <?php foreach ($franjas as $i => $franja): ?>
      <h2 class="h6 mt-4 mb-2"><?= h($franja[0]) ?> – <?= h($franja[1]) ?></h2>
      <?php if (!$por_franja[$i]): ?>
        <p class="text-muted small mb-0">Sin registros en esta franja.</p>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm table-striped align-middle mb-0">
            <thead>
              <tr>
                <th>Hora</th>
                <th class="text-end">Hum. %</th>
                <th class="text-end">Temp. °C</th>
                <th class="text-end">pH</th>
                <th class="text-end">CE µS/cm</th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($por_franja[$i] as $f): ?>
                <tr>
                  <td><?= h(substr($f['fecha_hora'], 11, 8)) ?></td>
                  <td class="text-end"><?= h(number_format((float) $f['humedad'], 1, '.', '')) ?></td>
                  <td class="text-end"><?= h(number_format((float) $f['temperatura'], 1, '.', '')) ?></td>
                  <td class="text-end"><?= h(number_format((float) $f['ph'], 1, '.', '')) ?></td>
                  <td class="text-end"><?= h((int) $f['ce']) ?></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    <?php endforeach; ?>
  <?php endif; ?>

  <a class="btn btn-outline-secondary w-100 mt-4" href="/">Volver a valores actuales</a>
</div>
</body>
</html>