#include "whisper.h"
#include "whisper_bridge.h"
#include <stdlib.h>
#include <string.h>

static struct whisper_context *g_ctx = NULL;

int rubai_load(const char *model_path) {
    if (g_ctx) return 0;
    struct whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = true;            // Metal (Apple GPU)
    cp.flash_attn = true;
    g_ctx = whisper_init_from_file_with_params(model_path, cp);
    return g_ctx ? 0 : 1;
}

void rubai_unload(void) {
    if (g_ctx) {
        whisper_free(g_ctx);
        g_ctx = NULL;
    }
}

char *rubai_transcribe(const float *samples, int n_samples, int n_threads) {
    if (!g_ctx) return NULL;

    struct whisper_full_params p =
        whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
    p.language          = "uz";          // faqat o'zbek
    p.translate         = false;
    p.beam_search.beam_size = 5;         // maksimal aniqlik
    p.n_threads         = n_threads > 0 ? n_threads : 4;
    p.no_timestamps     = true;
    p.print_progress    = false;
    p.print_realtime    = false;
    p.print_special     = false;
    p.print_timestamps  = false;
    p.suppress_blank    = true;

    if (whisper_full(g_ctx, p, samples, n_samples) != 0) return NULL;

    int ns = whisper_full_n_segments(g_ctx);
    size_t len = 0;
    char *out = malloc(1);
    if (!out) return NULL;
    out[0] = '\0';
    for (int i = 0; i < ns; i++) {
        const char *t = whisper_full_get_segment_text(g_ctx, i);
        if (!t) continue;
        size_t tl = strlen(t);
        char *tmp = realloc(out, len + tl + 1);
        if (!tmp) { free(out); return NULL; }
        out = tmp;
        memcpy(out + len, t, tl);
        len += tl;
        out[len] = '\0';
    }
    return out;
}

void rubai_free_str(char *s) { free(s); }
