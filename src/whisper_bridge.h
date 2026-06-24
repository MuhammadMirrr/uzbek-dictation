#ifndef RUBAI_WHISPER_BRIDGE_H
#define RUBAI_WHISPER_BRIDGE_H

// Modelni yuklaydi (bir marta). 0 = muvaffaqiyat.
int rubai_load(const char *model_path);

// Modelni RAM'dan bo'shatadi.
void rubai_unload(void);

// 16kHz mono float32 namunalardan lotin o'zbek matn qaytaradi.
// Qaytgan satrni rubai_free_str bilan bo'shating. NULL = xato.
char *rubai_transcribe(const float *samples, int n_samples, int n_threads);

void rubai_free_str(char *s);

#endif
