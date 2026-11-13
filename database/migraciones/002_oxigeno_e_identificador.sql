-- 002: oxigeno manual e identificador de lectura (RF01, RF09)
-- id_origen: identificador que genera quien envia la lectura (el ESP32 o el
--   navegador). Con el indice unico, un reenvio no crea una fila repetida.
-- atraso_s: segundos que tardo en llegar la lectura (0 = llego al instante).
-- La fecha y hora siguen asignandose en el servidor (RNF02).
-- Se puede ejecutar mas de una vez sin error (IF NOT EXISTS).

ALTER TABLE lectura
  ADD COLUMN IF NOT EXISTS id_origen VARCHAR(24) NULL AFTER ce,
  ADD COLUMN IF NOT EXISTS atraso_s INT UNSIGNED NOT NULL DEFAULT 0 AFTER id_origen,
  ADD UNIQUE KEY IF NOT EXISTS uq_lectura_id_origen (id_origen);

-- Oxigeno: captura manual desde la web. La unidad esta por confirmar con el
-- responsable del invernadero (mg/L o porcentaje); DECIMAL(5,2) sirve para ambas.
CREATE TABLE IF NOT EXISTS lectura_oxigeno (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  fecha_hora  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  oxigeno     DECIMAL(5,2) NOT NULL,
  id_origen   VARCHAR(24) NULL,
  atraso_s    INT UNSIGNED NOT NULL DEFAULT 0,
  UNIQUE KEY uq_oxigeno_id_origen (id_origen),
  INDEX idx_oxigeno_fecha_hora (fecha_hora)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
