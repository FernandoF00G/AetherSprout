#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "nvs_flash.h"
#include "config_local.h"
#include <stdbool.h>
#include <stdint.h>
#include "esp_random.h"
#include <stdio.h>
#include "esp_http_client.h"
#include "esp_timer.h"



static const char *TAG = "aethersprout";
static EventGroupHandle_t s_wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0

static void wifi_event_handler(void *arg, esp_event_base_t base,
                               int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
        ESP_LOGW(TAG, "WiFi no disponible, reintentando en 5 s...");
        vTaskDelay(pdMS_TO_TICKS(5000));
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = (ip_event_got_ip_t *)data;
        ESP_LOGI(TAG, "Conectado. IP del ESP32: " IPSTR, IP2STR(&ev->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                               &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               &wifi_event_handler, NULL));

    wifi_config_t wifi_config = {0};
    strncpy((char *)wifi_config.sta.ssid, WIFI_SSID,
            sizeof(wifi_config.sta.ssid) - 1);
    strncpy((char *)wifi_config.sta.password, WIFI_PASS,
            sizeof(wifi_config.sta.password) - 1);

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
}

typedef struct {
    float humedad;
    float temperatura;
    float ph;
    int   ce;
} lectura_t;

/* ---- Buffer sin conexión (RF09) ---- */
#define MAX_BUFFER_OFFLINE    60       /* lecturas que caben en RAM */
#define MAX_ENVIOS_POR_CICLO  10       /* máximo de envíos al vaciar el buffer */
#define MAX_ATRASO_S          172800   /* 48 h, igual que el servidor */

typedef struct {
    lectura_t lectura;
    uint32_t  seq;      /* número de lectura desde el arranque */
    int64_t   t_us;     /* instante de la muestra (esp_timer_get_time) */
} lectura_pendiente_t;

static lectura_pendiente_t s_buffer[MAX_BUFFER_OFFLINE];
static int      s_inicio = 0;      /* posición de la lectura más antigua */
static int      s_cuenta = 0;      /* lecturas pendientes */
static uint32_t s_arranque = 0;    /* identificador de este arranque */
static uint32_t s_seq = 0;

/* Guarda una lectura; si el buffer está lleno, descarta la más antigua */
static void buffer_agregar(const lectura_pendiente_t *p)
{
    if (s_cuenta == MAX_BUFFER_OFFLINE) {
        ESP_LOGW(TAG, "Buffer lleno: se descarta la lectura mas antigua");
        s_inicio = (s_inicio + 1) % MAX_BUFFER_OFFLINE;
        s_cuenta--;
    }
    s_buffer[(s_inicio + s_cuenta) % MAX_BUFFER_OFFLINE] = *p;
    s_cuenta++;
}

static void buffer_quitar_primera(void)
{
    s_inicio = (s_inicio + 1) % MAX_BUFFER_OFFLINE;
    s_cuenta--;
}

/* Número aleatorio entre min y max */
static float aleatorio(float min, float max)
{
    return min + ((float)esp_random() / (float)UINT32_MAX) * (max - min);
}

/* Lectura falsa, con valores típicos de un invernadero */
static lectura_t generar_lectura(void)
{
    lectura_t l;
    l.humedad     = aleatorio(55.0f, 75.0f);
    l.temperatura = aleatorio(20.0f, 28.0f);
    l.ph          = aleatorio(5.5f, 7.0f);
    l.ce          = 1200 + (int)(esp_random() % 1001);   /* 1200 a 2200 */
    return l;
}

/* Mismos rangos que valida el servidor */
static bool lectura_valida(const lectura_t *l)
{
    return l->humedad >= 0 && l->humedad <= 100 &&
           l->temperatura >= 0 && l->temperatura <= 55 &&
           l->ph >= 0 && l->ph <= 14 &&
           l->ce >= 0;
}

/* Envía una lectura al servidor, con su identificador y su atraso.
   Devuelve el código HTTP (201 = guardada, 200 = ya estaba guardada)
   o -1 si no hubo respuesta. */
static int enviar_lectura(const lectura_pendiente_t *p, int64_t ahora_us)
{
    char url[96];
    snprintf(url, sizeof(url), "http://%s:%d/api/lecturas.php",
             SERVER_IP, SERVER_PORT);

    int64_t atraso_s = (ahora_us - p->t_us) / 1000000;
    if (atraso_s < 0) {
        atraso_s = 0;
    }

    char cuerpo[192];
    snprintf(cuerpo, sizeof(cuerpo),
             "humedad=%.1f&temperatura=%.1f&ph=%.2f&ce=%d"
             "&id_origen=%08lx-%lu&segundos_atraso=%lu",
             p->lectura.humedad, p->lectura.temperatura, p->lectura.ph,
             p->lectura.ce, (unsigned long)s_arranque,
             (unsigned long)p->seq, (unsigned long)atraso_s);

    esp_http_client_config_t cfg = {
        .url = url,
        .method = HTTP_METHOD_POST,
        .timeout_ms = 5000,
    };
    esp_http_client_handle_t cliente = esp_http_client_init(&cfg);
    if (cliente == NULL) {
        ESP_LOGE(TAG, "No se pudo crear el cliente HTTP");
        return -1;
    }

    esp_http_client_set_header(cliente, "Content-Type",
                               "application/x-www-form-urlencoded");
    esp_http_client_set_post_field(cliente, cuerpo, strlen(cuerpo));

    int codigo = -1;
    esp_err_t err = esp_http_client_perform(cliente);
    if (err == ESP_OK) {
        codigo = esp_http_client_get_status_code(cliente);
        ESP_LOGI(TAG, "Enviado: %s -> respuesta HTTP %d", cuerpo, codigo);
    } else {
        ESP_LOGE(TAG, "Fallo al enviar: %s", esp_err_to_name(err));
    }
    esp_http_client_cleanup(cliente);
    return codigo;
}

/* Envía las lecturas pendientes, de la más antigua a la más nueva.
   Se detiene en el primer fallo y manda máximo MAX_ENVIOS_POR_CICLO. */
static void vaciar_buffer(void)
{
    int enviados = 0;
    while (s_cuenta > 0 && enviados < MAX_ENVIOS_POR_CICLO) {
        const lectura_pendiente_t *p = &s_buffer[s_inicio];
        int64_t ahora_us = esp_timer_get_time();

        if ((ahora_us - p->t_us) / 1000000 > MAX_ATRASO_S) {
            ESP_LOGE(TAG, "Lectura %lu con mas de 48 h de atraso: se descarta",
                     (unsigned long)p->seq);
            buffer_quitar_primera();
            continue;
        }

        int codigo = enviar_lectura(p, ahora_us);
        if (codigo == 201 || codigo == 200) {
            buffer_quitar_primera();       /* guardada, o ya estaba guardada */
            enviados++;
        } else if (codigo == 400) {
            ESP_LOGE(TAG, "El servidor rechazo la lectura %lu: se descarta",
                     (unsigned long)p->seq);
            buffer_quitar_primera();
            enviados++;
        } else {
            ESP_LOGW(TAG, "No se pudo enviar (codigo %d); se reintenta despues", codigo);
            break;
        }
    }
}

void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "Iniciando WiFi...");
    wifi_init_sta();

    s_arranque = esp_random();     /* identifica este arranque en id_origen */

    /* Al encender, da hasta 10 s para conectar; si no se logra, sigue y
       las lecturas quedan en el buffer hasta que haya red. */
    xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT,
                        pdFALSE, pdTRUE, pdMS_TO_TICKS(10000));

    TickType_t ultimo_ciclo = xTaskGetTickCount();
    while (1) {
        /* Siempre toma la muestra, haya o no WiFi */
        lectura_pendiente_t p;
        p.lectura = generar_lectura();
        if (lectura_valida(&p.lectura)) {
            p.seq = ++s_seq;
            p.t_us = esp_timer_get_time();
            buffer_agregar(&p);
        }

        if (xEventGroupGetBits(s_wifi_event_group) & WIFI_CONNECTED_BIT) {
            vaciar_buffer();
        } else {
            ESP_LOGW(TAG, "Sin WiFi: lectura guardada en el buffer");
        }

        if (s_cuenta > 0) {
            ESP_LOGW(TAG, "Lecturas pendientes en el buffer: %d de %d",
                     s_cuenta, MAX_BUFFER_OFFLINE);
        }

        vTaskDelayUntil(&ultimo_ciclo, pdMS_TO_TICKS(SEND_INTERVAL_S * 1000));
    }
}
