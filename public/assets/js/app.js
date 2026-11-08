/* AetherSprout - comportamiento minimo de la pantalla de valores actuales.
   La pagina funciona sin JavaScript (PHP pinta los valores); este archivo
   solo agrega: refresco cada 10 s, badge de conexion, captura de oxigeno
   y el semaforo de rangos. Requiere jQuery. */
(function ($) {
  'use strict';

  /* ---------------- Configuracion ---------------- */

  var API = '/api/lecturas.php';
  var INTERVALO_REFRESCO_MS = 10000;

  /* Unidad del oxigeno: por confirmar con el responsable del invernadero
     (la tabla dice "porosidad de aire %", el .md original proponia mg/L).
     Mientras este vacia, la pantalla indica "unidad por confirmar". */
  var UNIDAD_OXIGENO = '';

  /* Rangos de referencia del responsable. CE en uS/cm (1 mS/cm = 1000 uS/cm).
     El oxigeno NO entra al semaforo hasta aclarar su unidad. */
  var RANGOS_POR_TIPO = {
    fruto:   { nombre: 'Fruto (tomate, pimiento, pepino)',
               humedad: [70, 85], temperatura: [18, 25], ph: [5.5, 6.8], ce: [1500, 2500] },
    hoja:    { nombre: 'Hoja y flor (lechuga, espinaca, brócoli)',
               humedad: [65, 75], temperatura: [10, 18], ph: [6.0, 7.2], ce: [1000, 1800] },
    raiz:    { nombre: 'Raíz y tubérculo (zanahoria, rábano, papa)',
               humedad: [55, 65], temperatura: [12, 20], ph: [5.5, 6.8], ce: [1200, 2000] },
    semilla: { nombre: 'Semilla (legumbres)',
               humedad: [50, 60], temperatura: [15, 22], ph: [6.0, 7.5], ce: [1000, 1500] }
  };

  var CLAVE_CULTIVO = 'cultivo_activo';
  var CLAVE_CACHE = 'ultima_lectura_cache';
  var CLAVE_COLA = 'cola_oxigeno_offline';
  var MAX_COLA = 50;                 // capturas de oxigeno que se guardan sin conexion
  var MAX_ATRASO_S = 172800;         // 48 h, igual que la API
  var TIMEOUT_MS = 5000;
  var DECIMALES = { humedad: 1, temperatura: 1, ph: 2, ce: 0, oxigeno: 2 };

  /* ---------------- Cultivo elegido (solo en este navegador) ---------------- */

  function leerCultivo() {
    try {
      var c = window.localStorage.getItem(CLAVE_CULTIVO);
      return (c && RANGOS_POR_TIPO[c]) ? c : '';
    } catch (e) { return ''; }
  }

  function guardarCultivo(c) {
    try { window.localStorage.setItem(CLAVE_CULTIVO, c); } catch (e) { /* sin almacenamiento: queda solo en memoria */ }
  }

  var cultivo = leerCultivo();

  /* Lectura/escritura segura de JSON en localStorage (si falla, no pasa nada) */
  function leerJSON(clave, defecto) {
    try {
      var t = window.localStorage.getItem(clave);
      return t ? JSON.parse(t) : defecto;
    } catch (e) { return defecto; }
  }

  function guardarJSON(clave, valor) {
    try { window.localStorage.setItem(clave, JSON.stringify(valor)); } catch (e) { /* sin almacenamiento */ }
  }

  function dos(n) { return (n < 10 ? '0' : '') + n; }

  function horaLocal(ms) {
    var d = new Date(ms);
    return dos(d.getHours()) + ':' + dos(d.getMinutes()) + ':' + dos(d.getSeconds());
  }

  /* ---------------- Semaforo ---------------- */

  /* 'optimo', 'fuera' o null (sin cultivo, sin rango o sin valor) */
  function evaluar(medida, valor) {
    var tipo = RANGOS_POR_TIPO[cultivo];
    if (!tipo || !tipo[medida] || valor === null || isNaN(valor)) { return null; }
    return (valor >= tipo[medida][0] && valor <= tipo[medida][1]) ? 'optimo' : 'fuera';
  }

  function pintarSemaforo() {
    var $aviso = $('#aviso-rangos');
    if (!cultivo) {
      $aviso.text('Rangos sin configurar').removeClass('d-none');
    } else {
      $aviso.text('Rangos: ' + RANGOS_POR_TIPO[cultivo].nombre).removeClass('d-none');
    }

    $('.tarjeta-medida').each(function () {
      var $t = $(this);
      var medida = $t.data('medida');
      var crudo = $t.attr('data-valor');
      var valor = (crudo === undefined || crudo === '') ? null : parseFloat(crudo);
      var estado = evaluar(medida, valor);
      var $badge = $t.find('.estado-rango');

      $t.removeClass('border-danger border-success');
      $t.find('.valor').removeClass('text-danger');
      $badge.addClass('d-none').removeClass('bg-danger bg-success').text('');

      if (estado === 'fuera') {
        $t.addClass('border-danger');
        $t.find('.valor').addClass('text-danger');
        $badge.text('Fuera de rango').addClass('bg-danger').removeClass('d-none');
      } else if (estado === 'optimo') {
        $t.addClass('border-success');
        $badge.text('Óptimo').addClass('bg-success').removeClass('d-none');
      }
    });
  }

  /* ---------------- Tarjetas ---------------- */

  function formato(medida, valor) {
    return Number(valor).toFixed(DECIMALES[medida]);
  }

  function ponerValor(medida, valor) {
    var $t = $('.tarjeta-medida[data-medida="' + medida + '"]');
    if (!$t.length) { return; }
    if (valor === null || valor === undefined) {
      $t.attr('data-valor', '');
      $t.find('.valor').text('--');
    } else {
      $t.attr('data-valor', valor);
      $t.find('.valor').text(formato(medida, valor));
    }
  }

  function fechaLegible(texto) {            // "2026-11-07 19:39:22" -> "07/11/2026 19:39:22"
    var m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}:\d{2})$/.exec(texto || '');
    return m ? (m[3] + '/' + m[2] + '/' + m[1] + ' ' + m[4]) : '';
  }

  function pintarRespuesta(datos) {
    var l = datos && datos.lectura;
    var o = datos && datos.oxigeno;
    if (l) {
      ['humedad', 'temperatura', 'ph', 'ce'].forEach(function (m) { ponerValor(m, l[m]); });
      $('#fecha-ultima').text(fechaLegible(l.fecha_hora));
    }
    if (o) {
      ponerValor('oxigeno', o.oxigeno);
      $('#fecha-oxigeno').text(fechaLegible(o.fecha_hora));
    }
    pintarSemaforo();
  }

  /* ---------------- Badge de conexion ---------------- */

  function badge(enLinea) {
    var $b = $('#badge-conexion');
    if (enLinea) {
      $b.removeClass('bg-warning text-dark').addClass('bg-success').text('En línea');
    } else {
      $b.removeClass('bg-success').addClass('bg-warning text-dark').text('Sin conexión - Modo local');
    }
  }

  /* ---------------- Refresco ---------------- */

  /* ---------------- Cache local de la ultima lectura ---------------- */

  function notaCache() {
    var $n = $('#nota-cache');
    if (!$n.length) {
      $n = $('<span id="nota-cache" class="badge bg-secondary ms-2 d-none"></span>');
      $('#fecha-ultima').after($n);
    }
    return $n;
  }

  /* Sin servidor: marca los valores en pantalla como "cache local". Solo si la
     pantalla esta vacia se pintan los valores guardados. */
  function mostrarCache() {
    var c = leerJSON(CLAVE_CACHE, null);
    if (!c || !c.datos) { return; }
    if ($('#fecha-ultima').text() === '--') { pintarRespuesta(c.datos); }
    notaCache().text('caché local · guardado ' + horaLocal(c.guardado)).removeClass('d-none');
  }

  function ocultarNotaCache() {
    $('#nota-cache').addClass('d-none');
  }

  function sinConexion() {
    badge(false);
    mostrarCache();
  }

  /* ---------------- Refresco ---------------- */

  function refrescar() {
    $.ajax({ url: API + '?accion=ultima', dataType: 'json', timeout: TIMEOUT_MS })
      .done(function (datos) {
        badge(true);
        ocultarNotaCache();
        guardarJSON(CLAVE_CACHE, { datos: datos, guardado: Date.now() });
        pintarRespuesta(datos);
        enviarCola();
      })
      .fail(sinConexion);
  }

  /* ---------------- Captura manual de oxigeno ---------------- */

  function mensaje(texto, clase) {
    $('#msg-oxigeno').removeClass('text-success text-danger text-warning text-muted').addClass(clase).text(texto);
  }

  /* Identificador de la captura: letras/numeros en minuscula + "-" + segundos.
     Cumple el formato de la API (maximo 24 caracteres). Se genera ANTES de enviar,
     asi un reintento no crea una segunda fila. */
  function generarId() {
    var r = (Math.random().toString(36) + '00000').slice(2, 7);
    return 'nav' + r + '-' + Math.floor(Date.now() / 1000);
  }

  function datosOxigeno(item) {
    return {
      tipo_registro: 'oxigeno_manual',
      oxigeno: item.valor,
      id_origen: item.id,
      segundos_atraso: Math.max(0, Math.floor((Date.now() - item.t) / 1000))
    };
  }

  function enviarItem(item) {
    return $.ajax({ url: API, method: 'POST', data: datosOxigeno(item),
                    dataType: 'json', timeout: TIMEOUT_MS });
  }

  /* ---- Cola de capturas hechas sin conexion ---- */

  function pintarPendientes() {
    var n = leerJSON(CLAVE_COLA, []).length;
    var $p = $('#pendientes-oxigeno');
    if (!$p.length) {
      $p = $('<div id="pendientes-oxigeno" class="small text-warning-emphasis d-none"></div>');
      $('#msg-oxigeno').after($p);
    }
    if (n > 0) {
      $p.text(n + (n === 1 ? ' captura de oxígeno pendiente de enviar' : ' capturas de oxígeno pendientes de enviar'))
        .removeClass('d-none');
    } else {
      $p.addClass('d-none').text('');
    }
  }

  function encolar(item) {
    var cola = leerJSON(CLAVE_COLA, []);
    if (cola.length >= MAX_COLA) {
      mensaje('Sin conexión y la cola de este navegador está llena.', 'text-danger');
      return;
    }
    cola.push(item);
    guardarJSON(CLAVE_COLA, cola);
    $('#oxigeno').val('');
    mensaje('Sin conexión: guardado en este navegador, se enviará al reconectar.', 'text-warning');
    pintarPendientes();
  }

  function quitarPrimeraDeLaCola() {
    var cola = leerJSON(CLAVE_COLA, []);
    cola.shift();
    guardarJSON(CLAVE_COLA, cola);
  }

  var enviandoCola = false;

  /* Envia la cola en orden. Se detiene en el primer fallo de red. */
  function enviarCola() {
    if (enviandoCola || leerJSON(CLAVE_COLA, []).length === 0) { return; }
    enviandoCola = true;
    var enviadas = 0, descartadas = 0;

    function terminar() {
      enviandoCola = false;
      pintarPendientes();
      if (enviadas > 0) {
        mensaje(enviadas + (enviadas === 1 ? ' captura pendiente enviada.' : ' capturas pendientes enviadas.'), 'text-success');
        refrescar();
      }
      if (descartadas > 0) {
        mensaje(descartadas + (descartadas === 1 ? ' captura se descartó' : ' capturas se descartaron')
                + ' (el servidor la rechazó o pasó de 48 h).', 'text-warning');
      }
    }

    function siguiente() {
      var cola = leerJSON(CLAVE_COLA, []);
      if (cola.length === 0) { terminar(); return; }
      var item = cola[0];

      if ((Date.now() - item.t) / 1000 > MAX_ATRASO_S) {
        quitarPrimeraDeLaCola(); descartadas++; siguiente(); return;
      }
      enviarItem(item)
        .done(function () { quitarPrimeraDeLaCola(); enviadas++; siguiente(); })
        .fail(function (xhr) {
          if (xhr.status === 400) { quitarPrimeraDeLaCola(); descartadas++; siguiente(); }
          else { terminar(); }
        });
    }
    siguiente();
  }

  function enviarOxigeno(evento) {
    evento.preventDefault();
    var valor = $.trim($('#oxigeno').val());
    if (valor === '') { mensaje('Escribe un valor.', 'text-danger'); return; }

    var item = { valor: valor, id: generarId(), t: Date.now() };

    $('#form-oxigeno button[type="submit"]').prop('disabled', true);
    enviarItem(item).done(function () {
      badge(true);
      $('#oxigeno').val('');
      mensaje('Guardado.', 'text-success');
      refrescar();
    }).fail(function (xhr) {
      var r = xhr.responseJSON;
      if (xhr.status === 400 && r && r.detalle && r.detalle.oxigeno) {
        mensaje('Oxígeno ' + r.detalle.oxigeno + '.', 'text-danger');
      } else if (xhr.status === 0) {
        sinConexion();
        if (/^\d+(\.\d+)?$/.test(valor)) {
          encolar(item);       // misma id y misma hora: si el envio si llego, no se duplica
        } else {
          mensaje('Debe ser un número positivo con punto decimal.', 'text-danger');
        }
      } else {
        mensaje('No se pudo guardar (error ' + xhr.status + ').', 'text-danger');
      }
    }).always(function () {
      $('#form-oxigeno button[type="submit"]').prop('disabled', false);
    });
  }

  /* ---------------- Arranque ---------------- */

  $(function () {
    // Unidad del oxigeno
    if (UNIDAD_OXIGENO) {
      $('#unidad-oxigeno').text(UNIDAD_OXIGENO).removeClass('fst-italic');
    } else {
      $('#unidad-oxigeno').text('unidad por confirmar').addClass('fst-italic');
    }

    // Selector de cultivo
    var $sel = $('#selector-cultivo');
    if ($sel.length) {
      $.each(RANGOS_POR_TIPO, function (clave, tipo) {
        $sel.append($('<option>').val(clave).text(tipo.nombre));
      });
      $sel.val(cultivo).on('change', function () {
        cultivo = $(this).val();
        guardarCultivo(cultivo);
        pintarSemaforo();
      });
    }

    $('#form-oxigeno').on('submit', enviarOxigeno);
    $(window).on('offline', sinConexion);
    $(window).on('online', refrescar);

    pintarSemaforo();
    pintarPendientes();
    refrescar();
    setInterval(refrescar, INTERVALO_REFRESCO_MS);
  });

})(jQuery);
