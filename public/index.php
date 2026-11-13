<?php
require __DIR__ . '/../config/conexion.php';

function h($t): string
{
    return htmlspecialchars((string) $t, ENT_QUOTES, 'UTF-8');
}

// Unidad del oxigeno: por confirmar con el responsable del invernadero.
// Si se llena aqui, tambien hay que llenarla en public/assets/js/app.js (UNIDAD_OXIGENO).
$unidad_oxigeno = '';

$lectura = null;
$oxigeno = null;
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

// El oxigeno se consulta aparte: si falla, las demas tarjetas siguen funcionando
if (isset($pdo)) {
    try {
        $oxigeno = $pdo->query(
            'SELECT fecha_hora, oxigeno
             FROM lectura_oxigeno ORDER BY fecha_hora DESC, id DESC LIMIT 1'
        )->fetch();
    } catch (PDOException $e) {
        error_log('Error al consultar el oxigeno: ' . $e->getMessage());
    }
}

function fecha_legible(string $f): string
{
    return date('d/m/Y H:i:s', strtotime($f));
}

// Valor formateado y valor "crudo" para el semaforo; "--" si no hay dato
$v = [
    'humedad'     => $lectura ? number_format((float) $lectura['humedad'], 1, '.', '') : null,
    'temperatura' => $lectura ? number_format((float) $lectura['temperatura'], 1, '.', '') : null,
    'ph'          => $lectura ? number_format((float) $lectura['ph'], 2, '.', '') : null,
    'ce'          => $lectura ? (string) (int) $lectura['ce'] : null,
    'oxigeno'     => $oxigeno ? number_format((float) $oxigeno['oxigeno'], 2, '.', '') : null,
];
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Monitor del invernadero</title>
  <link href="/assets/css/bootstrap.min.css" rel="stylesheet">
  <noscript><style>#form-oxigeno, #bloque-cultivo { display: none; }</style></noscript>
</head>
<body class="bg-light">
<div class="container py-4" style="max-width: 600px;">
  <div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Monitor del invernadero</h1>
    <span id="badge-conexion" class="badge bg-success">En línea</span>
  </div>

  <?php if ($error): ?>
    <div class="alert alert-danger"><?= h($error) ?></div>
  <?php elseif (!$lectura): ?>
    <div class="alert alert-info">Aún no hay lecturas.</div>
  <?php endif; ?>

  <p class="text-muted mb-2">
    Última lectura:
    <strong id="fecha-ultima"><?= $lectura ? h(fecha_legible($lectura['fecha_hora'])) : '--' ?></strong>
  </p>

  <div id="bloque-cultivo" class="mb-3">
    <label for="selector-cultivo" class="form-label small text-muted mb-1">Tipo de hortaliza (para el semáforo)</label>
    <select id="selector-cultivo" class="form-select form-select-sm">
      <option value="">Sin configurar</option>
    </select>
    <div id="aviso-rangos" class="small text-muted mt-1 d-none"></div>
  </div>

  <div class="row g-3 mb-4">
    <div class="col-6">
      <div class="card text-center h-100 tarjeta-medida" data-medida="humedad" data-valor="<?= h($v['humedad'] ?? '') ?>">
        <div class="card-body">
          <div class="text-muted">Humedad</div>
          <div class="fs-2"><span class="valor"><?= h($v['humedad'] ?? '--') ?></span> %</div>
          <span class="estado-rango badge d-none"></span>
        </div>
      </div>
    </div>
    <div class="col-6">
      <div class="card text-center h-100 tarjeta-medida" data-medida="temperatura" data-valor="<?= h($v['temperatura'] ?? '') ?>">
        <div class="card-body">
          <div class="text-muted">Temperatura</div>
          <div class="fs-2"><span class="valor"><?= h($v['temperatura'] ?? '--') ?></span> °C</div>
          <span class="estado-rango badge d-none"></span>
        </div>
      </div>
    </div>
    <div class="col-6">
      <div class="card text-center h-100 tarjeta-medida" data-medida="ph" data-valor="<?= h($v['ph'] ?? '') ?>">
        <div class="card-body">
          <div class="text-muted">pH</div>
          <div class="fs-2 valor"><?= h($v['ph'] ?? '--') ?></div>
          <span class="estado-rango badge d-none"></span>
        </div>
      </div>
    </div>
    <div class="col-6">
      <div class="card text-center h-100 tarjeta-medida" data-medida="ce" data-valor="<?= h($v['ce'] ?? '') ?>">
        <div class="card-body">
          <div class="text-muted">CE</div>
          <div class="fs-2 valor"><?= h($v['ce'] ?? '--') ?></div>
          <div class="small text-muted">µS/cm</div>
          <span class="estado-rango badge d-none"></span>
        </div>
      </div>
    </div>
    <div class="col-12">
      <div class="card text-center tarjeta-medida" data-medida="oxigeno" data-valor="<?= h($v['oxigeno'] ?? '') ?>">
        <div class="card-body">
          <div class="text-muted">Oxígeno (captura manual)</div>
          <div class="fs-2 valor"><?= h($v['oxigeno'] ?? '--') ?></div>
          <div class="small text-muted">
            <span id="unidad-oxigeno"><?= $unidad_oxigeno !== '' ? h($unidad_oxigeno) : 'unidad por confirmar' ?></span>
            · capturado: <span id="fecha-oxigeno"><?= $oxigeno ? h(fecha_legible($oxigeno['fecha_hora'])) : '--' ?></span>
          </div>

          <form id="form-oxigeno" class="row g-2 justify-content-center mt-2" autocomplete="off">
            <div class="col-6">
              <label for="oxigeno" class="visually-hidden">Valor de oxígeno</label>
              <input type="text" inputmode="decimal" id="oxigeno" class="form-control form-control-sm"
                     placeholder="Valor medido">
            </div>
            <div class="col-4">
              <button type="submit" class="btn btn-success btn-sm w-100">Guardar</button>
            </div>
            <div class="col-12 small" id="msg-oxigeno" role="status"></div>
          </form>
        </div>
      </div>
    </div>
  </div>

  <a class="btn btn-success w-100" href="/registros.php">Consultar registros</a>
</div>
<script src="/assets/js/jquery-3.7.1.min.js"></script>
<script src="/assets/js/app.js"></script>
</body>
</html>
