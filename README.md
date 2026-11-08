# AetherSprout: monitor de invernadero

**Estado: Sprint 2 en desarrollo** (el Sprint 1 está cerrado y marcado con el tag `sprint-1`)

Proyecto Turing EC · Actividad AA6 "Del MVP al Sprint 1: diseño mínimo para comenzar a desarrollar".

## Problema

Quien monitorea un invernsadero (por ejemplo, un estudiante de Agronegocios) lleva hoy los registros de humedad, temperatura, pH, conductividad eléctrica y oxígeno a mano, en papel, y después los transcribe. Eso hace difícil conservarlos y consultarlos de forma confiable. AetherSprout busca registrar las mediciones con fecha y hora, guardarlas de forma persistente y permitir consultarlas por fecha.

## Qué hace el Sprint 1

- Un **ESP32** funciona como **simulador de datos**: genera una lectura de humedad, temperatura, pH y conductividad eléctrica (CE) y la envía por HTTP al servidor a un intervalo configurable. Todavía no hay sensores conectados.
- El **servidor PHP** valida la lectura, le asigna la fecha y hora y la guarda en **MariaDB**.
- Una página web (adaptable a celular) muestra:
  - **Valores actuales:** la última lectura guardada.
  - **Registros por fecha:** las lecturas de un día elegido, agrupadas en 6 franjas de 4 horas.

**Requisitos del MVP incluidos:** RF01 (con 4 de las 5 variables), RF02, RF03 y RF04.
**Fuera de este sprint:** oxígeno (se mide a mano), RF09 (conservar mediciones sin conexión), RF05 a RF08, RF10, sensores reales y pantalla LCD.

## Qué agrega el Sprint 2 (en desarrollo)

- **Oxígeno manual (RF01 completo):** una tarjeta y un formulario en la pantalla de valores actuales. Se guarda en una tabla aparte (`lectura_oxigeno`) y se muestra en los registros por fecha, bajo la franja que corresponde.
- **Conservar lecturas sin conexión (RF09):** el ESP32 guarda en RAM hasta 60 lecturas cuando el servidor o el WiFi no están disponibles y las envía al reconectar, de la más antigua a la más nueva, con su hora real. La captura de oxígeno hecha en el navegador sin conexión también se conserva y se envía al volver la conexión.
- **Sin duplicados:** cada lectura lleva un identificador (`id_origen`) y un reenvío no crea otra fila.
- **Valores actuales con refresco automático** cada 10 segundos, indicador de conexión y **semáforo de rangos** por tipo de hortaliza (los rangos los dio el responsable del invernadero).
- **jQuery 3.7.1** (copia local, con su hash verificado) para el refresco, el formulario de oxígeno y el indicador de conexión.
- **Migraciones numeradas** de la base (`scripts/actualizar-bd.ps1`).

## Integrantes

| Integrante | Usuario de GitHub | Sprint 1 | Sprint 2 |
|---|---|---|---|
| Fernando Emmanuel Rodríguez Pérez | [@FernandoF00G](https://github.com/FernandoF00G) | Servidor PHP, API y pantallas | Firmware del ESP32 y pruebas contra el servidor |
| Laura Teresa Vidales Pérez | [@Schattendwollef](https://github.com/Schattendwollef) | Firmware del ESP32 y pruebas de base de datos y respaldo | Base de datos, API y pantallas |

Cuando una persona trabaja en la computadora de la otra, el commit se firma con el nombre de quien hizo el trabajo (`git commit --author="Nombre <correo>"`).

## Tecnologías

| Componente | Tecnología |
|---|---|
| Interfaz web | HTML y Bootstrap 5.3.8 (solo CSS, copia local), generados desde PHP; jQuery 3.7.1 (copia local) para el refresco y los formularios |
| Servidor | PHP 8.2 con el servidor integrado (`php -S`); el código es compatible con PHP 7.4 |
| Acceso a datos | PDO (`pdo_mysql`) |
| Base de datos | MariaDB |
| Microcontrolador | ESP32 NodeMCU-32S |
| Firmware | C con ESP-IDF 5.3.x en VS Code |
| Comunicación | HTTP POST en red local, sin HTTPS |
| Entorno | Scripts de PowerShell y winget |

## Estructura del repositorio

```
public/                    Páginas web y API (raíz del servidor)
  index.php                Valores actuales (con oxígeno manual y semáforo)
  registros.php            Registros por fecha
  api/lecturas.php         Guarda y consulta lecturas y oxígeno (POST y GET)
  assets/css/              Bootstrap 5 (copia local)
  assets/js/               jQuery 3.7.1 (copia local) y app.js
config/                    Conexión a la base; config.example.php es la plantilla
database/migraciones/      Estructura de la base (SQL numerado: 001, 002, ...)
scripts/                   Instalación, servidor, base de datos, respaldo y jQuery
firmware/                  Proyecto ESP-IDF del ESP32
```

## Cómo ejecutarlo

### 1. Servidor web y base de datos (Windows 10/11)

1. Clonar el repositorio en una ruta sin espacios, por ejemplo `C:\proyectos\AetherSprout`.
2. Abrir **PowerShell como administrador** (se recomienda PowerShell 7) en esa carpeta. Si PowerShell 7 se abre sin elevar, abrir *Windows PowerShell* como administrador y escribir `pwsh`.
3. Instalar el entorno (Git, VS Code, PHP 8.2 y MariaDB; activa las extensiones de PHP, registra el servicio de MariaDB, crea la base `monitor_invernadero` y el usuario `invernadero`, y abre el puerto 8000 en redes privadas):
```
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\scripts\instalar.ps1
```
   El script pide las contraseñas de `root` y de `invernadero`; **cada equipo usa las suyas** y no se suben al repositorio.
4. Preparar el servidor (genera `config\config.php`, aplica la migración y muestra la IP del equipo):
```
   .\scripts\preparar-servidor.ps1
```
5. Arrancar el servidor desde la raíz del repositorio y dejar la ventana abierta:
```
   php -S 0.0.0.0:8000 -t public
```
6. Abrir `http://127.0.0.1:8000/`. La red de Windows debe estar en perfil **Privada** para que otros dispositivos lleguen al puerto 8000 (se cambia desde la configuración de red, o con `Set-NetConnectionProfile` usando el `InterfaceAlias` que muestra `Get-NetConnectionProfile`).

`config\config.php` contiene la contraseña de la base y **no se sube a Git** (lo ignora `.gitignore`).

### 2. Probar la API sin la placa

Con el servidor arrancado, en **una sola línea**:

```
curl.exe -i -d "humedad=60&temperatura=23.5&ph=6.5&ce=1700" http://127.0.0.1:8000/api/lecturas.php
```

Respuesta esperada: `201`. Con datos fuera de rango (por ejemplo `humedad=150`) responde `400` y no guarda nada.

**Contrato de la API** (`/api/lecturas.php`, respuestas en JSON):

| Método | Qué hace | Campos |
|---|---|---|
| `POST` | Guarda una lectura | `humedad` (0–100), `temperatura` (0–55), `ph` (0–14), `ce` (entero ≥ 0), con punto decimal |
| `POST` | Guarda una captura de oxígeno | `tipo_registro=oxigeno_manual`, `oxigeno` (0–100, rango provisional) |
| `GET` | Última lectura y último oxígeno | `?accion=ultima` (o sin parámetros) |
| `GET` | Registros de un día en 6 franjas de 4 horas | `?accion=registros&fecha=AAAA-MM-DD` |

Campos opcionales en los dos `POST`:
- `id_origen`: identificador único (`letras o números en minúscula`, guion y número, por ejemplo `a1b2c3d4-17`). Si ya existe responde `200` con `"duplicada":true` y no guarda otra fila.
- `segundos_atraso`: entero de 0 a 172800 (48 horas). El servidor guarda la lectura con la hora actual menos ese atraso.

La fecha y hora las asigna el servidor. Códigos: `201` guardada, `200` duplicada, `400` datos inválidos, `405` método no permitido (`Allow: GET, POST`), `500` error del servidor.

### Base de datos: aplicar migraciones

Antes de actualizar una base que ya tiene datos, hacer un respaldo (sección 4) y después:

```
.\scripts\actualizar-bd.ps1
```

Aplica solo las migraciones que faltan (`database/migraciones/NNN_*.sql`) y registra cuáles ya aplicó. Se puede ejecutar todas las veces que haga falta.

### jQuery

La copia de jQuery 3.7.1 ya está en el repositorio (`public/assets/js/`), así que el servidor no necesita internet. Para volver a descargarla y verificarla contra el hash oficial de https://releases.jquery.com/:

```
pwsh -ExecutionPolicy Bypass -File .\scripts\instalar-jquery.ps1 -HashEsperado "sha256-..."
```

### 3. Firmware del ESP32

1. Instalar VS Code con la extensión **Espressif IDF** y ESP-IDF **5.3.x**, con objetivo `esp32`.
2. Abrir en VS Code la carpeta `firmware/` (la que contiene `CMakeLists.txt`). La ruta no debe tener espacios.
3. Copiar `firmware/main/config_local.example.h` como `firmware/main/config_local.h` y editar:
   - `WIFI_SSID` y `WIFI_PASS`: la red de **2.4 GHz**.
   - `SERVER_IP`: la IP del equipo que corre el servidor (`ipconfig`, "Dirección IPv4" del adaptador WiFi).
   - `SERVER_PORT`: 8000.
   - `SEND_INTERVAL_S`: 30 para pruebas, 300 para el valor oficial.
4. `config_local.h` **no se sube a Git** (lo ignora `firmware/.gitignore`).
5. Conectar la placa con un **cable USB de datos**, elegir el puerto COM, compilar, grabar y abrir el monitor serie.
6. En el monitor debe verse `Conectado.` y, en cada intervalo, `Enviado: ... id_origen=... segundos_atraso=0 -> respuesta HTTP 201`.
7. Prueba de caída del servidor: detener `php -S` unos minutos. El monitor muestra `Lecturas pendientes en el buffer: N de 60`. Al reiniciar el servidor, la placa envía hasta 10 lecturas por intervalo, de la más antigua a la más nueva, con su `segundos_atraso` real.

### 4. Respaldo de la base

```
.\scripts\respaldar-bd.ps1
```

Crea un archivo `.sql` en `backups\` (carpeta que no se sube a Git).

## Limitaciones conocidas

- La comunicación es **HTTP sin HTTPS ni autenticación**; solo debe usarse en una red local de confianza.
- La **IP del servidor va dentro del firmware**: si el equipo servidor cambia de red o de IP, hay que actualizar `SERVER_IP` y volver a grabar la placa.
- Las lecturas sin conexión se guardan en la **RAM** de la placa (hasta 60): se **pierden si la placa se reinicia o se va la luz**, y si se llena el buffer se descarta la más antigua. Una lectura con más de 48 horas de atraso se descarta. El intervalo oficial de 300 s no se ha probado todavía (se probó con 30 s).
- Las capturas de oxígeno hechas sin conexión se guardan en el **navegador** (hasta 50) y se pierden si se borran los datos del sitio o se usa modo privado. La caché de la última lectura también vive solo en ese navegador.
- La **unidad del oxígeno está por confirmar** con el responsable del invernadero (la tabla habla de porosidad de aire en %), y el rango de validación (0–100) es provisional. El oxígeno no entra al semáforo.
- El **semáforo** usa los rangos por tipo de hortaliza dados por el responsable; el tipo se elige en pantalla y se recuerda solo en ese navegador. Falta confirmar qué tipo de hortaliza hay en el invernadero y que los sensores reales midan lo que dice la tabla (humedad como capacidad de campo y temperatura del suelo). Con datos simulados el semáforo no tiene significado agronómico.
- Los valores son **simulados**. La conductividad eléctrica (CE) se muestra en µS/cm y el método para obtenerla con el sensor real está por validar.
- Tras unirse a una red nueva, la placa puede tardar unos minutos en lograr conectar con el servidor; conviene dejar margen antes de una demostración.
- El servidor integrado de PHP es para desarrollo; la forma de despliegue se decidirá en un sprint posterior.

## Seguridad

No se suben al repositorio contraseñas, el nombre ni la clave del WiFi, ni `config\config.php` ni `firmware/main/config_local.h`. Las plantillas (`config.example.php` y `config_local.example.h`) llevan valores de ejemplo.