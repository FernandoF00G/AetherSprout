-- 003: usuarios, sitios, plantios, dispositivos, bitacora e inmutabilidad (Sprint 3)
-- RF01, RF02, RF09, RF10 y RNF02.
-- Se puede ejecutar mas de una vez sin error (IF NOT EXISTS en todo).
-- Orden: tablas nuevas -> datos iniciales -> columnas nuevas -> llenar lo existente
--        -> llaves foraneas -> bitacora -> triggers (al final, para no bloquear el llenado).
-- Archivo en ASCII a proposito: actualizar-bd.ps1 lo pasa por una tuberia de
-- PowerShell que convertiria los acentos en "?".


-- ===================== 1) Tablas nuevas =====================

-- Cuentas. Las de Moodle se identifican por moodle_id (no se guarda su usuario
-- ni su contrasena de Moodle). Las locales (superusuario) usan usuario + contrasena_hash.
CREATE TABLE IF NOT EXISTS usuarios (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  moodle_id       INT UNSIGNED NULL,
  usuario         VARCHAR(50) NULL,
  nombre          VARCHAR(120) NOT NULL,
  rol             ENUM('alumno','profesor','administrador','superusuario') NOT NULL DEFAULT 'alumno',
  autorizado      TINYINT(1) NOT NULL DEFAULT 0,
  contrasena_hash VARCHAR(255) NULL,
  eliminado       TINYINT(1) NOT NULL DEFAULT 0,
  eliminado_en    DATETIME NULL,
  creado_en       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_usuarios_moodle_id (moodle_id),
  UNIQUE KEY uq_usuarios_usuario (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Sitios fisicos donde se mide
CREATE TABLE IF NOT EXISTS ubicaciones (
  id     INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL,
  tipo   ENUM('invernadero','malla_sombra','pruebas') NOT NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  UNIQUE KEY uq_ubicaciones_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Ciclo de cultivo en un sitio. fecha_fin vacia = plantio activo.
-- ubicacion_activa es una columna que calcula MariaDB: vale ubicacion_id mientras
-- el plantio esta activo y NULL cuando se cierra. Su indice UNICO impide tener dos
-- plantios activos en el mismo sitio (varios NULL si se permiten).
CREATE TABLE IF NOT EXISTS plantios (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  ubicacion_id     INT UNSIGNED NOT NULL,
  nombre           VARCHAR(80) NOT NULL,
  tipo_hortaliza   ENUM('fruto','hoja','raiz','semilla') NOT NULL,
  fecha_inicio     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_fin        DATETIME NULL,
  abierto_por      INT UNSIGNED NULL,
  cerrado_por      INT UNSIGNED NULL,
  ubicacion_activa INT UNSIGNED AS (IF(fecha_fin IS NULL, ubicacion_id, NULL)) PERSISTENT,
  UNIQUE KEY uq_plantios_activo_por_ubicacion (ubicacion_activa),
  KEY idx_plantios_ubicacion (ubicacion_id),
  CONSTRAINT fk_plantios_ubicacion FOREIGN KEY (ubicacion_id) REFERENCES ubicaciones (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_plantios_abierto_por FOREIGN KEY (abierto_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_plantios_cerrado_por FOREIGN KEY (cerrado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Que sitios puede ver cada alumno (profesores y niveles superiores ven todos)
CREATE TABLE IF NOT EXISTS asignaciones (
  usuario_id   INT UNSIGNED NOT NULL,
  ubicacion_id INT UNSIGNED NOT NULL,
  asignado_por INT UNSIGNED NULL,
  asignado_en  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (usuario_id, ubicacion_id),
  KEY idx_asignaciones_ubicacion (ubicacion_id),
  CONSTRAINT fk_asignaciones_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_asignaciones_ubicacion FOREIGN KEY (ubicacion_id) REFERENCES ubicaciones (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_asignaciones_asignado_por FOREIGN KEY (asignado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Placas ESP32. identificador es lo que manda la placa; la clave se guarda con hash.
CREATE TABLE IF NOT EXISTS dispositivos (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  identificador   VARCHAR(32) NOT NULL,
  ubicacion_id    INT UNSIGNED NOT NULL,
  clave_hash      VARCHAR(255) NOT NULL,
  activo          TINYINT(1) NOT NULL DEFAULT 1,
  creado_en       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ultimo_contacto DATETIME NULL,
  UNIQUE KEY uq_dispositivos_identificador (identificador),
  KEY idx_dispositivos_ubicacion (ubicacion_id),
  CONSTRAINT fk_dispositivos_ubicacion FOREIGN KEY (ubicacion_id) REFERENCES ubicaciones (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Bitacora de auditoria (RNF02): quien hizo que, a quien y cuando.
-- usuario_id NULL = lo hizo un script o el sistema.
CREATE TABLE IF NOT EXISTS bitacora (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  fecha_hora          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  usuario_id          INT UNSIGNED NULL,
  accion              VARCHAR(50) NOT NULL,
  objeto              VARCHAR(30) NULL,
  objeto_id           INT UNSIGNED NULL,
  usuario_afectado_id INT UNSIGNED NULL,
  detalle             TEXT NULL,
  KEY idx_bitacora_fecha_hora (fecha_hora),
  CONSTRAINT fk_bitacora_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_bitacora_usuario_afectado FOREIGN KEY (usuario_afectado_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ===================== 2) Datos iniciales =====================

-- Los cuatro sitios. Si ya existen (por el nombre unico), no se duplican.
INSERT INTO ubicaciones (nombre, tipo) VALUES
  ('Invernadero 1', 'invernadero'),
  ('Invernadero 2', 'invernadero'),
  ('Mallasombra',   'malla_sombra'),
  ('Pruebas',       'pruebas')
ON DUPLICATE KEY UPDATE id = id;

-- Plantio de ejemplo, solo en el sitio Pruebas. Empieza en la fecha del primer
-- registro que exista (lectura u oxigeno) para que todo lo anterior quede dentro.
INSERT INTO plantios (ubicacion_id, nombre, tipo_hortaliza, fecha_inicio)
SELECT u.id, 'Plantio de pruebas', 'hoja',
       COALESCE((SELECT MIN(t.fecha_hora)
                 FROM (SELECT fecha_hora FROM lectura
                       UNION ALL
                       SELECT fecha_hora FROM lectura_oxigeno) AS t), NOW())
FROM ubicaciones u
WHERE u.nombre = 'Pruebas'
  AND NOT EXISTS (SELECT 1 FROM plantios p WHERE p.ubicacion_id = u.id);


-- ===================== 3) Columnas nuevas en lectura y oxigeno =====================

-- hortaliza: en algunas computadoras ya existe (la agrego una migracion local que
-- nunca llego al repositorio). Aqui se crea donde falte, para que todas las bases
-- queden iguales. Queda OBSOLETA: el tipo de hortaliza se toma del plantio.
ALTER TABLE lectura
  ADD COLUMN IF NOT EXISTS hortaliza      VARCHAR(40)  NULL AFTER fecha_hora,
  ADD COLUMN IF NOT EXISTS ubicacion_id   INT UNSIGNED NULL AFTER atraso_s,
  ADD COLUMN IF NOT EXISTS plantio_id     INT UNSIGNED NULL AFTER ubicacion_id,
  ADD COLUMN IF NOT EXISTS dispositivo_id INT UNSIGNED NULL AFTER plantio_id,
  ADD INDEX IF NOT EXISTS idx_lectura_ubicacion_fecha (ubicacion_id, fecha_hora),
  ADD INDEX IF NOT EXISTS idx_lectura_plantio (plantio_id),
  ADD INDEX IF NOT EXISTS idx_lectura_dispositivo (dispositivo_id);

ALTER TABLE lectura
  MODIFY COLUMN hortaliza VARCHAR(40) NULL DEFAULT NULL
  COMMENT 'Obsoleta desde 003: el tipo de hortaliza se toma del plantio';

-- usuario_id: quien capturo el oxigeno (los registros anteriores quedan sin dato)
ALTER TABLE lectura_oxigeno
  ADD COLUMN IF NOT EXISTS ubicacion_id INT UNSIGNED NULL AFTER atraso_s,
  ADD COLUMN IF NOT EXISTS plantio_id   INT UNSIGNED NULL AFTER ubicacion_id,
  ADD COLUMN IF NOT EXISTS usuario_id   INT UNSIGNED NULL AFTER plantio_id,
  ADD INDEX IF NOT EXISTS idx_oxigeno_ubicacion_fecha (ubicacion_id, fecha_hora),
  ADD INDEX IF NOT EXISTS idx_oxigeno_plantio (plantio_id),
  ADD INDEX IF NOT EXISTS idx_oxigeno_usuario (usuario_id);


-- ===================== 4) Lo existente pasa a Pruebas =====================
-- Solo toca filas vacias: si se repite, no encuentra ninguna y no cambia nada.

UPDATE lectura
SET ubicacion_id = (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas')
WHERE ubicacion_id IS NULL;

UPDATE lectura
SET plantio_id = (SELECT p.id FROM plantios p
                  JOIN ubicaciones u ON u.id = p.ubicacion_id
                  WHERE u.nombre = 'Pruebas' AND p.nombre = 'Plantio de pruebas')
WHERE plantio_id IS NULL
  AND ubicacion_id = (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas');

UPDATE lectura_oxigeno
SET ubicacion_id = (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas')
WHERE ubicacion_id IS NULL;

UPDATE lectura_oxigeno
SET plantio_id = (SELECT p.id FROM plantios p
                  JOIN ubicaciones u ON u.id = p.ubicacion_id
                  WHERE u.nombre = 'Pruebas' AND p.nombre = 'Plantio de pruebas')
WHERE plantio_id IS NULL
  AND ubicacion_id = (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas');


-- ===================== 5) Llaves foraneas =====================
-- RESTRICT: no se puede borrar un sitio, plantio, dispositivo o usuario que tenga
-- registros. Nada se borra "en cascada" (las cascadas no pasarian por los triggers).

ALTER TABLE lectura
  ADD CONSTRAINT fk_lectura_ubicacion FOREIGN KEY IF NOT EXISTS (ubicacion_id)
    REFERENCES ubicaciones (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT fk_lectura_plantio FOREIGN KEY IF NOT EXISTS (plantio_id)
    REFERENCES plantios (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT fk_lectura_dispositivo FOREIGN KEY IF NOT EXISTS (dispositivo_id)
    REFERENCES dispositivos (id) ON DELETE RESTRICT ON UPDATE RESTRICT;

ALTER TABLE lectura_oxigeno
  ADD CONSTRAINT fk_oxigeno_ubicacion FOREIGN KEY IF NOT EXISTS (ubicacion_id)
    REFERENCES ubicaciones (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT fk_oxigeno_plantio FOREIGN KEY IF NOT EXISTS (plantio_id)
    REFERENCES plantios (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  ADD CONSTRAINT fk_oxigeno_usuario FOREIGN KEY IF NOT EXISTS (usuario_id)
    REFERENCES usuarios (id) ON DELETE RESTRICT ON UPDATE RESTRICT;


-- ===================== 6) Rastro en la bitacora =====================

INSERT INTO bitacora (accion, objeto, detalle)
SELECT 'migracion', 'esquema',
       CONCAT('003: lecturas y oxigeno existentes asignados al sitio Pruebas (',
              (SELECT COUNT(*) FROM lectura), ' lecturas, ',
              (SELECT COUNT(*) FROM lectura_oxigeno), ' de oxigeno)')
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM bitacora WHERE accion = 'migracion' AND detalle LIKE '003:%');


-- ===================== 7) Triggers =====================

-- 7a) Al insertar: si no viene el sitio, va a Pruebas; si no viene el plantio,
--     se usa el plantio activo de ese sitio (o queda vacio si no hay).
--     Asi la API actual sigue funcionando sin cambios hasta F1b.
CREATE TRIGGER IF NOT EXISTS lectura_asignar_sitio
BEFORE INSERT ON lectura
FOR EACH ROW
SET NEW.ubicacion_id = COALESCE(NEW.ubicacion_id,
                                (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas')),
    NEW.plantio_id   = COALESCE(NEW.plantio_id,
                                (SELECT id FROM plantios
                                 WHERE ubicacion_activa = COALESCE(NEW.ubicacion_id,
                                       (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas'))));

CREATE TRIGGER IF NOT EXISTS oxigeno_asignar_sitio
BEFORE INSERT ON lectura_oxigeno
FOR EACH ROW
SET NEW.ubicacion_id = COALESCE(NEW.ubicacion_id,
                                (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas')),
    NEW.plantio_id   = COALESCE(NEW.plantio_id,
                                (SELECT id FROM plantios
                                 WHERE ubicacion_activa = COALESCE(NEW.ubicacion_id,
                                       (SELECT id FROM ubicaciones WHERE nombre = 'Pruebas'))));

-- 7b) Inmutabilidad (RNF02): nadie puede modificar ni borrar estos registros.
CREATE TRIGGER IF NOT EXISTS lectura_sin_cambios
BEFORE UPDATE ON lectura
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: las lecturas no se pueden modificar';

CREATE TRIGGER IF NOT EXISTS lectura_sin_borrar
BEFORE DELETE ON lectura
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: las lecturas no se pueden borrar';

CREATE TRIGGER IF NOT EXISTS oxigeno_sin_cambios
BEFORE UPDATE ON lectura_oxigeno
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: el oxigeno registrado no se puede modificar';

CREATE TRIGGER IF NOT EXISTS oxigeno_sin_borrar
BEFORE DELETE ON lectura_oxigeno
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: el oxigeno registrado no se puede borrar';

CREATE TRIGGER IF NOT EXISTS bitacora_sin_cambios
BEFORE UPDATE ON bitacora
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: la bitacora no se puede modificar';

CREATE TRIGGER IF NOT EXISTS bitacora_sin_borrar
BEFORE DELETE ON bitacora
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'RNF02: la bitacora no se puede borrar';
