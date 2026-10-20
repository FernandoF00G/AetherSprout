# AetherSprout: monitor de invernadero

**Estado: Sprint 1 en desarrollo**

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

## Integrantes

| Integrante | Usuario de GitHub | Parte principal |
|---|---|---|
| Fernando Emmanuel Rodríguez Pérez | [@FernandoF00G](https://github.com/FernandoF00G) | Servidor PHP, API y pantallas |
| Laura Teresa Vidales Pérez | [@Schattendwollef](https://github.com/Schattendwollef) | Firmware del ESP32 y pruebas de base de datos y respaldo |

## Tecnologías

| Componente | Tecnología |
|---|---|
| Interfaz web | HTML y Bootstrap 5.3.8 (solo CSS, copia local), generados desde PHP |
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
  index.php                Valores actuales
  registros.php            Registros por fecha
  api/lecturas.php         Recibe y guarda lecturas (POST)
  assets/css/              Bootstrap 5 (copia local)
config/                    Conexión a la base; config.example.php es la plantilla
database/migraciones/      Estructura de la base (SQL numerado)
scripts/                   Instalación, preparación del servidor, base de datos y respaldo
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

Contrato de la API: `POST /api/lecturas.php`, `Content-Type: application/x-www-form-urlencoded`, campos `humedad` (0–100), `temperatura` (0–55), `ph` (0–14) y `ce` (entero ≥ 0), con punto decimal. La fecha y hora las asigna el servidor.

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
6. En el monitor debe verse `Conectado.` y, en cada intervalo, `Enviado: ... respuesta HTTP 201`.

### 4. Respaldo de la base

```
.\scripts\respaldar-bd.ps1
```

Crea un archivo `.sql` en `backups\` (carpeta que no se sube a Git).

## Limitaciones conocidas del Sprint 1

- La comunicación es **HTTP sin HTTPS ni autenticación**; solo debe usarse en una red local de confianza.
- La **IP del servidor va dentro del firmware**: si el equipo servidor cambia de red o de IP, hay que actualizar `SERVER_IP` y volver a grabar la placa.
- Las lecturas que se generan mientras el servidor o el WiFi no están disponibles **se pierden** (conservarlas sin conexión es RF09, del siguiente sprint).
- Los valores son **simulados**. La conductividad eléctrica (CE) se muestra en µS/cm y el método para obtenerla con el sensor real está por validar.
- Tras unirse a una red nueva, la placa puede tardar unos minutos en lograr conectar con el servidor; conviene dejar margen antes de una demostración.
- El servidor integrado de PHP es para desarrollo; la forma de despliegue se decidirá en un sprint posterior.

## Seguridad

No se suben al repositorio contraseñas, el nombre ni la clave del WiFi, ni `config\config.php` ni `firmware/main/config_local.h`. Las plantillas (`config.example.php` y `config_local.example.h`) llevan valores de ejemplo.