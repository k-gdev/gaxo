/*
 * Gaxo — C shim around the UxPlay engine.
 * Copyright (C) 2026 Gaxo contributors. GPL-3.0-or-later.
 *
 * Mirrors what UxPlay's uxplay.cpp (v1.73.7) does around lib/:
 * start_dnssd() feature bits, start_raop_server() setup, register_dnssd(),
 * and the reset path that drops clients and restarts the listener.
 */
#include "gaxo_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dnssd.h"
#include "logger.h"
#include "raop.h"
#include "stream.h"

struct gaxo_engine {
    raop_t *raop;
    dnssd_t *dnssd;
    gaxo_engine_callbacks cb;
    char *name;
    char *device_id;
    char *keyfile;
    unsigned short port;
    bool advertise;
    bool registered;
    float volume_db;
};

/* ---- engine callbacks (called on UxPlay threads) ---- */

static void on_log(void *cls, int level, const char *msg) {
    gaxo_engine *e = cls;
    if (e->cb.log) e->cb.log(e->cb.ctx, level, msg);
}

static void on_conn_init(void *cls) {
    gaxo_engine *e = cls;
    if (e->cb.conn_opened) e->cb.conn_opened(e->cb.ctx);
}

static void on_conn_destroy(void *cls) {
    gaxo_engine *e = cls;
    if (e->cb.conn_closed) e->cb.conn_closed(e->cb.ctx);
}

static void on_conn_reset(void *cls, int reason) {
    gaxo_engine *e = cls;
    if (e->cb.conn_lost) e->cb.conn_lost(e->cb.ctx, reason);
}

static void on_conn_feedback(void *cls) {
    gaxo_engine *e = cls;
    if (e->cb.feedback) e->cb.feedback(e->cb.ctx);
}

static void on_video_reset(void *cls, reset_type_t type) {
    gaxo_engine *e = cls;
    switch (type) {
    case RESET_TYPE_NOHOLD:
    case RESET_TYPE_RTP_SHUTDOWN:
    case RESET_TYPE_RTP_TO_HLS_TEARDOWN:
        if (e->cb.video_stopped) e->cb.video_stopped(e->cb.ctx);
        break;
    default: /* HLS reset types: HLS is not advertised */
        break;
    }
}

static int on_video_set_codec(void *cls, video_codec_t codec) {
    /* H.265 is not advertised (feature bit 42 off); only H.264 is accepted. */
    return codec == VIDEO_CODEC_H264 ? 0 : -1;
}

static void on_video_process(void *cls, raop_ntp_t *ntp, video_decode_struct *data) {
    gaxo_engine *e = cls;
    if (e->cb.video_frame && !data->is_h265) {
        e->cb.video_frame(e->cb.ctx, data->data, data->data_len, data->ntp_time_remote);
    }
}

static void on_video_pause(void *cls) {
    on_log(cls, LOGGER_DEBUG, "gaxo: video paused");
}

static void on_video_resume(void *cls) {
    on_log(cls, LOGGER_DEBUG, "gaxo: video resumed");
}

static void on_video_flush(void *cls) {
    gaxo_engine *e = cls;
    if (e->cb.video_flush) e->cb.video_flush(e->cb.ctx);
}

static void on_video_report_size(void *cls, float *width_source, float *height_source, float *width,
                                 float *height) {
    gaxo_engine *e = cls;
    if (e->cb.video_size) e->cb.video_size(e->cb.ctx, *width_source, *height_source, *width, *height);
}

static void on_audio_process(void *cls, raop_ntp_t *ntp, audio_decode_struct *data) {
    gaxo_engine *e = cls;
    if (e->cb.audio_frame) {
        e->cb.audio_frame(e->cb.ctx, data->data, data->data_len, data->ct, data->ntp_time_remote);
    }
}

static void on_audio_flush(void *cls) {
    gaxo_engine *e = cls;
    if (e->cb.audio_flush) e->cb.audio_flush(e->cb.ctx);
}

static void on_audio_get_format(void *cls, unsigned char *ct, unsigned short *spf, bool *using_screen,
                                bool *is_media, uint64_t *audio_format) {
    gaxo_engine *e = cls;
    if (e->cb.audio_format) e->cb.audio_format(e->cb.ctx, *ct, *spf);
}

static double on_audio_set_client_volume(void *cls) {
    gaxo_engine *e = cls;
    return e->volume_db;
}

static void on_audio_set_volume(void *cls, float volume) {
    gaxo_engine *e = cls;
    e->volume_db = volume;
    if (e->cb.volume) e->cb.volume(e->cb.ctx, volume);
}

static void on_report_client_request(void *cls, char *device_id, char *model, char *name, bool *admit) {
    gaxo_engine *e = cls;
    *admit = true;
    if (e->cb.client_request) {
        e->cb.client_request(e->cb.ctx, device_id ? device_id : "", model ? model : "", name ? name : "", admit);
    }
}

static void on_display_pin(void *cls, char *pin) {
    gaxo_engine *e = cls;
    if (e->cb.show_pin) e->cb.show_pin(e->cb.ctx, pin);
}

/* ---- setup helpers ---- */

static bool parse_device_id(const char *device_id, char hw_addr[6]) {
    unsigned int b[6];
    char tail;
    if (!device_id ||
        sscanf(device_id, "%2x:%2x:%2x:%2x:%2x:%2x%c", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5], &tail) != 6) {
        return false;
    }
    for (int i = 0; i < 6; i++) hw_addr[i] = (char) b[i];
    return true;
}

/* Feature bits exactly as uxplay.cpp start_dnssd() sets them, with HLS off,
 * H.265 off, and bit 27 (legacy pairing) on only in PIN mode. */
static void set_features(dnssd_t *dnssd, bool pin_once) {
    static const int bits[32] = {
        0, 1, 1, 0,  0, 1, 1, 1,  0, 1, 1, 1,  1, 1, 1, 1,
        1, 1, 1, 1,  1, 1, 1, 0,  0, 1, 0, 1,  1, 0, 1, 0,
    };
    for (int i = 0; i < 32; i++) dnssd_set_airplay_features(dnssd, i, bits[i]);
    dnssd_set_airplay_features(dnssd, 0, 0);  /* HLS video */
    dnssd_set_airplay_features(dnssd, 4, 0);  /* HLS */
    dnssd_set_airplay_features(dnssd, 42, 0); /* screen multi-codec (H.265) */
    dnssd_set_airplay_features(dnssd, 27, pin_once ? 1 : 0);
}

static char *dup_or_empty(const char *s) {
    return strdup(s ? s : "");
}

static void free_engine(gaxo_engine *e) {
    if (!e) return;
    if (e->raop) raop_destroy(e->raop);
    if (e->dnssd) dnssd_destroy(e->dnssd);
    free(e->name);
    free(e->device_id);
    free(e->keyfile);
    free(e);
}

/* ---- public API ---- */

int gaxo_engine_start(const gaxo_engine_config *config, const gaxo_engine_callbacks *callbacks,
                      gaxo_engine **out) {
    *out = NULL;
    gaxo_engine *e = calloc(1, sizeof(*e));
    if (!e) return GAXO_ERR_RAOP_INIT;
    if (callbacks) e->cb = *callbacks;
    e->name = dup_or_empty(config->name);
    e->device_id = dup_or_empty(config->device_id);
    e->keyfile = dup_or_empty(config->keyfile);
    e->advertise = config->advertise;
    e->volume_db = 0.0f;

    char hw_addr[6];
    if (!parse_device_id(e->device_id, hw_addr)) {
        free_engine(e);
        return GAXO_ERR_DNSSD_INIT;
    }

    int error = 0;
    e->dnssd = dnssd_init(e->name, (int) strlen(e->name), hw_addr, sizeof(hw_addr), &error,
                          config->pin_once ? 1 : 0);
    if (error || !e->dnssd) {
        e->dnssd = NULL;
        free_engine(e);
        return GAXO_ERR_DNSSD_INIT;
    }
    set_features(e->dnssd, config->pin_once);

    raop_callbacks_t cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.cls = e;
    cbs.conn_init = on_conn_init;
    cbs.conn_destroy = on_conn_destroy;
    cbs.conn_reset = on_conn_reset;
    cbs.conn_feedback = on_conn_feedback;
    cbs.audio_process = on_audio_process;
    cbs.video_process = on_video_process;
    cbs.audio_flush = on_audio_flush;
    cbs.video_flush = on_video_flush;
    cbs.video_pause = on_video_pause;
    cbs.video_resume = on_video_resume;
    cbs.audio_set_client_volume = on_audio_set_client_volume;
    cbs.audio_set_volume = on_audio_set_volume;
    cbs.audio_get_format = on_audio_get_format;
    cbs.video_report_size = on_video_report_size;
    cbs.report_client_request = on_report_client_request;
    cbs.display_pin = on_display_pin;
    cbs.video_reset = on_video_reset;
    cbs.video_set_codec = on_video_set_codec;

    e->raop = raop_init(&cbs);
    if (!e->raop) {
        free_engine(e);
        return GAXO_ERR_RAOP_INIT;
    }
    raop_set_log_callback(e->raop, on_log, e);
    raop_set_log_level(e->raop, config->log_level);

    /* nohold = 0: a second client is refused while one is connected. */
    if (raop_init2(e->raop, 0, e->device_id, e->keyfile)) {
        free(e->raop); /* uxplay.cpp frees, not destroys, after a failed raop_init2 */
        e->raop = NULL;
        free_engine(e);
        return GAXO_ERR_RAOP_INIT;
    }

    if (config->width) raop_set_plist(e->raop, "width", config->width);
    if (config->height) raop_set_plist(e->raop, "height", config->height);
    if (config->refresh_rate) raop_set_plist(e->raop, "refreshRate", config->refresh_rate);
    if (config->max_fps) raop_set_plist(e->raop, "maxFPS", config->max_fps);
    /* Like `uxplay -pin nnnn`: stored as code + 10000 so the engine keeps it after each attempt. */
    if (config->pin_once && config->fixed_pin >= 0 && config->fixed_pin <= 9999) {
        raop_set_plist(e->raop, "pin", config->fixed_pin + 10000);
    }

    /* Same mapping as `uxplay -p <base>`: TCP/UDP base, base+1, base+2.
     * TCP base = mirror data, base+1 = RTSP/HTTP. 0 = dynamic. */
    unsigned short base = config->base_port;
    unsigned short tcp[3] = {0, 0, 0};
    unsigned short udp[3] = {0, 0, 0};
    if (base) {
        for (int i = 0; i < 3; i++) tcp[i] = udp[i] = (unsigned short) (base + i);
    }
    raop_set_tcp_ports(e->raop, tcp);
    raop_set_udp_ports(e->raop, udp);

    e->port = raop_get_port(e->raop);
    if (raop_start_httpd(e->raop, &e->port) < 0) {
        free_engine(e);
        return GAXO_ERR_PORT;
    }
    raop_set_port(e->raop, e->port);
    raop_set_dnssd(e->raop, e->dnssd);

    if (e->advertise) {
        if (dnssd_register_raop(e->dnssd, e->port) || dnssd_register_airplay(e->dnssd, e->port)) {
            dnssd_unregister_raop(e->dnssd);
            dnssd_unregister_airplay(e->dnssd);
            free_engine(e);
            return GAXO_ERR_REGISTER;
        }
        e->registered = true;
    }

    *out = e;
    return GAXO_OK;
}

uint16_t gaxo_engine_port(const gaxo_engine *engine) {
    return engine ? engine->port : 0;
}

void gaxo_engine_drop_clients(gaxo_engine *engine) {
    if (!engine) return;
    raop_stop_httpd(engine->raop);
    raop_remove_known_connections(engine->raop);
    unsigned short port = engine->port;
    raop_start_httpd(engine->raop, &port);
    raop_set_port(engine->raop, port);
    engine->port = port;
}

void gaxo_engine_stop(gaxo_engine *engine) {
    if (!engine) return;
    if (engine->registered) {
        dnssd_unregister_raop(engine->dnssd);
        dnssd_unregister_airplay(engine->dnssd);
    }
    free_engine(engine);
}
