-- 001: tabla de lecturas (RF01, RF02, RF03, RF04)
-- La fecha y hora la asigna el servidor (MariaDB), no el ESP32.
CREATE TABLE IF NOT EXISTS lectura (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  fecha_hora  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  humedad     DECIMAL(5,2) NOT NULL,
  temperatura DECIMAL(5,2) NOT NULL,
  ph          DECIMAL(4,2) NOT NULL,
  ce          INT UNSIGNED NOT NULL,
  INDEX idx_fecha_hora (fecha_hora)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
