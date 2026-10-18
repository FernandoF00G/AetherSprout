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

/* Envía la lectura al servidor. Devuelve el código HTTP (201 = guardada)
   o -1 si no hubo respuesta. */
static int enviar_lectura(const lectura_t *l)
{
    char url[96];
    snprintf(url, sizeof(url), "http://%s:%d/api/lecturas.php",
             SERVER_IP, SERVER_PORT);

    char cuerpo[128];
    snprintf(cuerpo, sizeof(cuerpo),
             "humedad=%.1f&temperatura=%.1f&ph=%.2f&ce=%d",
             l->humedad, l->temperatura, l->ph, l->ce);

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


void app_main(void)
{
    /*esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "Iniciando WiFi...");
    wifi_init_sta();

    xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT,
                        pdFALSE, pdTRUE, portMAX_DELAY);
    ESP_LOGI(TAG, "WiFi listo");

            lectura_t l = generar_lectura();
    if (lectura_valida(&l)) {
        enviar_lectura(&l);
    }*/

    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "Iniciando WiFi...");
    wifi_init_sta();

    while (1) {
        /* Espera hasta 10 s a tener WiFi; si no hay, no envía y vuelve a esperar */
        EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group,
                                               WIFI_CONNECTED_BIT,
                                               pdFALSE, pdTRUE,
                                               pdMS_TO_TICKS(10000));
        if (bits & WIFI_CONNECTED_BIT) {
            lectura_t l = generar_lectura();
            if (lectura_valida(&l)) {
                int codigo = enviar_lectura(&l);
                if (codigo != 201) {
                    ESP_LOGW(TAG, "El servidor no guardo la lectura (codigo %d)", codigo);
                }
            }
            vTaskDelay(pdMS_TO_TICKS(SEND_INTERVAL_S * 1000));
        } else {
            ESP_LOGW(TAG, "Sin WiFi, no se envia; se reintenta...");
        }
    }

}