#include "llama.h"

#include <vector>
#include <string>
#include <cstring>

static llama_model* g_model = nullptr;
static llama_context* g_ctx = nullptr;
static llama_sampler* g_sampler = nullptr;
static bool g_streaming = false;
static int g_stream_generated_tokens = 0;
static constexpr int k_max_stream_tokens = 200;
static std::string g_stream_piece;

static bool has_gguf_extension(const char* model_path) {
    if (!model_path) return false;
    const std::string path(model_path);
    constexpr char kExt[] = ".gguf";
    constexpr size_t kExtLen = sizeof(kExt) - 1;
    return path.size() >= kExtLen &&
           path.compare(path.size() - kExtLen, kExtLen, kExt) == 0;
}

extern "C" {

void flutter_free();
bool flutter_stream_start(const char* prompt);
const char* flutter_stream_next();

bool flutter_load_model(const char* model_path,
                        const char* mmproj_path) {
    // Reserved for separate multimodal projection loading in future revisions.
    (void) mmproj_path;

    if (!has_gguf_extension(model_path)) return false;

    flutter_free();

    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 100;


    g_model = llama_model_load_from_file(model_path, mparams);
    if (!g_model) return false;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 4096;
    cparams.n_batch = 512;

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) return false;

    g_sampler = llama_sampler_init_greedy();

    return true;
}


const char* flutter_generate(const char* prompt) {
    static std::string result;
    result.clear();

    if (!flutter_stream_start(prompt)) {
        return nullptr;
    }

    while (const char* piece = flutter_stream_next()) {
        result.append(piece);
    }

    return result.c_str();
}

bool flutter_stream_start(const char* prompt) {
    if (!g_ctx || !g_model || !g_sampler || !prompt) return false;

    g_streaming = false;
    g_stream_generated_tokens = 0;

    const llama_vocab* vocab = llama_model_get_vocab(g_model);

    llama_chat_message msgs[1];
    msgs[0].role = "user";
    msgs[0].content = prompt;

    char formatted_buf[8192];

    int32_t formatted_len = llama_chat_apply_template(
        nullptr,
        msgs,
        1,
        true,
        formatted_buf,
        sizeof(formatted_buf)
    );

    if (formatted_len <= 0) return false;

    std::vector<llama_token> tokens(4096);

    int n_tokens = llama_tokenize(
        vocab,
        formatted_buf,
        formatted_len,
        tokens.data(),
        tokens.size(),
        true,
        true
    );

    if (n_tokens <= 0) return false;

    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);

    if (llama_decode(g_ctx, batch) != 0) return false;

    g_streaming = true;
    return true;
}

const char* flutter_stream_next() {
    if (!g_streaming || !g_ctx || !g_model || !g_sampler) return nullptr;

    const llama_vocab* vocab = llama_model_get_vocab(g_model);

    while (g_stream_generated_tokens < k_max_stream_tokens) {
        llama_token new_token = llama_sampler_sample(g_sampler, g_ctx, -1);
        g_stream_generated_tokens++;

        if (new_token == llama_vocab_eos(vocab)) {
            g_streaming = false;
            return nullptr;
        }

        char piece[128];
        int n = llama_token_to_piece(
            vocab,
            new_token,
            piece,
            sizeof(piece),
            0,
            false
        );

        llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        if (llama_decode(g_ctx, next_batch) != 0) {
            g_streaming = false;
            return nullptr;
        }

        if (n <= 0) {
            continue;
        }

        g_stream_piece.assign(piece, n);
        return g_stream_piece.c_str();
    }

    g_streaming = false;
    return nullptr;
}





void flutter_free() {
    g_streaming = false;
    g_stream_generated_tokens = 0;
    g_stream_piece.clear();

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

    llama_backend_free();
}
}
