/*
 * Gaxo — C shim around the UxPlay engine.
 * Copyright (C) 2026 Gaxo contributors. GPL-3.0-or-later.
 *
 * This is the only header Swift sees. It replaces what uxplay.cpp does around
 * UxPlay's lib/: Bonjour (dnssd) and raop server lifecycle, AirPlay feature
 * bits, and the engine callbacks.
 */
#ifndef GAXO_ENGINE_H
#define GAXO_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct gaxo_engine gaxo_engine;

enum {
    GAXO_OK = 0,
    GAXO_ERR_DNSSD_INIT = -1,
    GAXO_ERR_RAOP_INIT = -2,
    GAXO_ERR_PORT = -3,
    GAXO_ERR_REGISTER = -4,
};

typedef struct {
    const char *name;        /* name shown on the iPhone */
    const char *device_id;   /* "02:AB:CD:EF:01:23" — locally administered MAC */
    const char *keyfile;     /* PEM path; the Ed25519 identity key is persisted here */
    uint16_t base_port;      /* TCP+UDP base..base+2; 0 = dynamic */
    uint16_t width, height, refresh_rate, max_fps;
    bool pin_once;           /* UxPlay -pin mode: 4-digit code on first connection */
    bool advertise;          /* register _airplay._tcp / _raop._tcp with Bonjour */
    int log_level;           /* UxPlay LOGGER_* level, 0..8 */
    int fixed_pin;           /* with pin_once: 0..9999 = always this code; -1 = random each time */
} gaxo_engine_config;

/* Every pointer may be NULL. All callbacks run on engine threads. */
typedef struct {
    void *ctx;
    void (*log)(void *ctx, int level, const char *msg);
    void (*client_request)(void *ctx, const char *device_id, const char *model, const char *name, bool *admit);
    void (*conn_opened)(void *ctx);
    void (*conn_closed)(void *ctx);
    void (*conn_lost)(void *ctx, int reason);
    void (*feedback)(void *ctx);
    void (*video_stopped)(void *ctx);
    void (*video_frame)(void *ctx, const uint8_t *data, int len, uint64_t ntp_remote_ns);
    void (*video_size)(void *ctx, float width_source, float height_source, float width, float height);
    void (*video_flush)(void *ctx);
    void (*audio_format)(void *ctx, uint8_t ct, uint16_t spf);
    void (*audio_frame)(void *ctx, const uint8_t *data, int len, uint8_t ct, uint64_t ntp_remote_ns);
    void (*audio_flush)(void *ctx);
    void (*volume)(void *ctx, float db);
    void (*show_pin)(void *ctx, const char *pin);
} gaxo_engine_callbacks;

/* Starts the engine. On success *out is set and GAXO_OK returned; otherwise
 * *out is NULL and one of the GAXO_ERR_* codes is returned. The config strings
 * are copied. */
int gaxo_engine_start(const gaxo_engine_config *config, const gaxo_engine_callbacks *callbacks,
                      gaxo_engine **out);

/* The TCP port the engine listens on. */
uint16_t gaxo_engine_port(const gaxo_engine *engine);

/* Drops every connected client and restarts the listener on the same port. */
void gaxo_engine_drop_clients(gaxo_engine *engine);

/* Unregisters Bonjour, stops the server and frees the engine. NULL is a no-op. */
void gaxo_engine_stop(gaxo_engine *engine);

#ifdef __cplusplus
}
#endif

#endif /* GAXO_ENGINE_H */
