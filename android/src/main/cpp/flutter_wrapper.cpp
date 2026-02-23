#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#include "llama.h"
#include "mtmd.h"

#include <vector>
#include <string>
#include <cstring>
#include <iostream>

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;
static mtmd_context* g_mtmd_ctx = nullptr;

static void run_generation_impl(const char* prompt, const char* image_path, void (*callback)(const char*), std::string* out_result);

extern "C" {

bool flutter_load_model(const char* model_path,
                        const char* mmproj_path) {

    // Cleanup first
    if (g_sampler) { llama_sampler_free(g_sampler); g_sampler = nullptr; }
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
    if (g_mtmd_ctx) { mtmd_free(g_mtmd_ctx); g_mtmd_ctx = nullptr; }

    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 99;

    g_model = llama_model_load_from_file(model_path, mparams);
    if (!g_model) return false;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 4096;
    cparams.n_batch = 512;

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) return false;

    // Load MMProj if path provided
    if (mmproj_path && strlen(mmproj_path) > 0) {
        struct mtmd_context_params mtmd_params = mtmd_context_params_default();
        g_mtmd_ctx = mtmd_init_from_file(mmproj_path, g_model, mtmd_params);
        if (!g_mtmd_ctx) {
             // Failed to load mmproj
             return false;
        }
    }

    g_sampler = llama_sampler_init_greedy();

    return true;
}

void flutter_close() {
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }

    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }

    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }

    if (g_mtmd_ctx) {
        mtmd_free(g_mtmd_ctx);
        g_mtmd_ctx = nullptr;
    }

    llama_backend_free();
}

const char* flutter_generate(const char* prompt, const char* image_path) {
    static std::string result;
    result.clear();
    run_generation_impl(prompt, image_path, nullptr, &result);
    return result.c_str();
}

void flutter_stream(const char* prompt, const char* image_path, void (*callback)(const char*)) {
    run_generation_impl(prompt, image_path, callback, nullptr);
}

} // extern "C"

// Implementation of run_generation_impl
static void run_generation_impl(const char* prompt, const char* image_path, void (*callback)(const char*), std::string* out_result) {
    if (!g_ctx || !g_model) return;

    // Clear KV cache
    // llama_kv_cache_clear(g_ctx); // Deprecated/Removed
    llama_memory_clear(llama_get_memory(g_ctx), true);

    int n_past = 0;

    // --- Prompt Processing ---
    if (g_mtmd_ctx) {
         mtmd_bitmap* bitmap = nullptr;
         if (image_path && strlen(image_path) > 0) {
             int x, y, c;
             unsigned char * data = stbi_load(image_path, &x, &y, &c, 3);
             if (data) {
                 bitmap = mtmd_bitmap_init(x, y, data);
                 stbi_image_free(data);
             }
         }

         struct mtmd_input_text text_inp;
         text_inp.text = prompt;
         text_inp.add_special = true;
         text_inp.parse_special = true;

         const mtmd_bitmap* bitmaps[1] = { bitmap };
         size_t n_bitmaps = bitmap ? 1 : 0;

         mtmd_input_chunks* chunks = mtmd_input_chunks_init();
         if (mtmd_tokenize(g_mtmd_ctx, chunks, &text_inp, bitmaps, n_bitmaps) != 0) {
              if (bitmap) mtmd_bitmap_free(bitmap);
              mtmd_input_chunks_free(chunks);
              return;
         }

         size_t n_chunks = mtmd_input_chunks_size(chunks);
         for (size_t i = 0; i < n_chunks; i++) {
             const mtmd_input_chunk* chunk = mtmd_input_chunks_get(chunks, i);
             enum mtmd_input_chunk_type type = mtmd_input_chunk_get_type(chunk);
             size_t n_tokens_chunk = mtmd_input_chunk_get_n_tokens(chunk);

             if (type == MTMD_INPUT_CHUNK_TYPE_TEXT) {
                 size_t n_tok_text;
                 const llama_token* tokens = mtmd_input_chunk_get_tokens_text(chunk, &n_tok_text);

                 llama_batch batch = llama_batch_init(n_tok_text, 0, 1);
                 batch.n_tokens = n_tok_text;
                 for (int k=0; k<n_tok_text; k++) {
                     batch.token[k] = tokens[k];
                     batch.pos[k] = n_past + k;
                     batch.n_seq_id[k] = 1;
                     batch.seq_id[k][0] = 0;
                     batch.logits[k] = false;
                 }
                 if (i == n_chunks - 1) batch.logits[n_tok_text - 1] = true;

                 llama_decode(g_ctx, batch);
                 llama_batch_free(batch);
                 n_past += n_tok_text;

             } else if (type == MTMD_INPUT_CHUNK_TYPE_IMAGE) {
                 if (mtmd_encode_chunk(g_mtmd_ctx, chunk) == 0) {
                     float* embd = mtmd_get_output_embd(g_mtmd_ctx);
                     int n_embd = llama_model_n_embd(g_model);

                     llama_batch batch = llama_batch_init(n_tokens_chunk, n_embd, 1);
                     batch.n_tokens = n_tokens_chunk;
                     for (int k=0; k<n_tokens_chunk; k++) {
                         batch.token[k] = 0;
                         memcpy(batch.embd + k*n_embd, embd + k*n_embd, n_embd * sizeof(float));
                         batch.pos[k] = n_past + k;
                         batch.n_seq_id[k] = 1;
                         batch.seq_id[k][0] = 0;
                         batch.logits[k] = false;
                     }
                     if (i == n_chunks - 1) batch.logits[n_tokens_chunk - 1] = true;

                     llama_decode(g_ctx, batch);
                     llama_batch_free(batch);
                     n_past += n_tokens_chunk;
                 }
             }
         }

         if (bitmap) mtmd_bitmap_free(bitmap);
         mtmd_input_chunks_free(chunks);
    } else {
        // Standard Tokenization
        std::vector<llama_token> tokens_list(strlen(prompt) + 2);
        const llama_vocab* vocab = llama_model_get_vocab(g_model);
        int n_tokens = llama_tokenize(vocab, prompt, strlen(prompt), tokens_list.data(), tokens_list.size(), true, true);
        if (n_tokens < 0) {
             tokens_list.resize(-n_tokens);
             n_tokens = llama_tokenize(vocab, prompt, strlen(prompt), tokens_list.data(), tokens_list.size(), true, true);
        }

        if (n_tokens > 0) {
             llama_batch batch = llama_batch_init(n_tokens, 0, 1);
             batch.n_tokens = n_tokens;
             for (int k=0; k<n_tokens; k++) {
                 batch.token[k] = tokens_list[k];
                 batch.pos[k] = n_past + k;
                 batch.n_seq_id[k] = 1;
                 batch.seq_id[k][0] = 0;
                 batch.logits[k] = false;
             }
             batch.logits[n_tokens-1] = true;

             llama_decode(g_ctx, batch);
             llama_batch_free(batch);
             n_past += n_tokens;
        }
    }

    // --- Generation Loop ---
    const int max_tokens = 512;
    const llama_vocab* vocab = llama_model_get_vocab(g_model);

    for (int i = 0; i < max_tokens; i++) {
        llama_token new_token = llama_sampler_sample(g_sampler, g_ctx, -1);

        if (llama_vocab_is_eog(vocab, new_token)) {
             break;
        }

        char piece[256];
        int n = llama_token_to_piece(vocab, new_token, piece, sizeof(piece), 0, true);
        if (n < 0) {
             continue;
        }
        std::string piece_str(piece, n);

        if (callback) {
            callback(piece_str.c_str());
        }
        if (out_result) {
            out_result->append(piece_str);
        }

        // Prepare next batch
        llama_batch batch = llama_batch_init(1, 0, 1);
        batch.n_tokens = 1;
        batch.token[0] = new_token;
        batch.pos[0] = n_past;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;

        n_past += 1;

        if (llama_decode(g_ctx, batch) != 0) {
            llama_batch_free(batch);
            break;
        }
        llama_batch_free(batch);
    }
}
