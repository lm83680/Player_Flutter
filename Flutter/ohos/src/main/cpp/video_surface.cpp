// Copyright (c) 2026 Tencent. All rights reserved.
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <native_buffer/buffer_common.h>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <map>
#include <poll.h>
#include <string>
#include <time.h>
#include <unistd.h>
#include <vector>

namespace {
struct Surface {
    OHNativeWindow *window;
    int width;
    int height;
};
// Each JS environment owns its surfaces; no process-global player/surface state.
struct Surfaces {
    std::map<int, Surface> values;
    int next = 1;
    ~Surfaces() {
        for (const auto &entry : values) OH_NativeWindow_DestroyNativeWindow(entry.second.window);
    }
};
napi_value Number(napi_env env, int value) {
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}
std::string String(napi_env env, napi_value value) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &size) != napi_ok) return "";
    std::vector<char> bytes(size + 1);
    napi_get_value_string_utf8(env, value, bytes.data(), bytes.size(), &size);
    return std::string(bytes.data(), size);
}
napi_value CreateOutput(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    void *data = nullptr;
    napi_get_cb_info(env, info, &argc, args, nullptr, &data);
    if (argc != 1) return Number(env, -8);
    std::string path = String(env, args[0]);
    int fd = open(path.c_str(), O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0600);
    return Number(env, fd >= 0 ? fd : (errno == EEXIST ? -7 : -8));
}
napi_value OpenSurface(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    void *data = nullptr;
    napi_get_cb_info(env, info, &argc, args, nullptr, &data);
    auto *state = static_cast<Surfaces *>(data);
    int w = 0, h = 0;
    if (argc != 3 || napi_get_value_int32(env, args[1], &w) != napi_ok ||
        napi_get_value_int32(env, args[2], &h) != napi_ok || w <= 0 || h <= 0) return Number(env, -1);
    std::string id = String(env, args[0]);
    char *end = nullptr;
    uint64_t surfaceId = strtoull(id.c_str(), &end, 10);
    OHNativeWindow *window = nullptr;
    if (id.empty() || !end || *end || OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &window) != 0)
        return Number(env, -1);
    uint64_t usage = NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_MEM_DMA;
    bool ok = OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, w, h) == 0 &&
        OH_NativeWindow_NativeWindowHandleOpt(window, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888) == 0 &&
        OH_NativeWindow_NativeWindowHandleOpt(window, SET_USAGE, usage) == 0 &&
        OH_NativeWindow_NativeWindowHandleOpt(window, SET_TIMEOUT, 0) == 0;
    if (!ok) {
        OH_NativeWindow_DestroyNativeWindow(window);
        return Number(env, -1);
    }
    int handle = state->next++;
    state->values.emplace(handle, Surface {window, w, h});
    return Number(env, handle);
}
napi_value Boolean(napi_env env, bool value) {
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}
napi_value WriteFrame(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    void *data = nullptr;
    napi_get_cb_info(env, info, &argc, args, nullptr, &data);
    auto *state = static_cast<Surfaces *>(data);
    int handle = 0, stride = 0;
    bool bgra = false, success = false;
    void *source = nullptr;
    size_t length = 0;
    if (argc != 4 || napi_get_value_int32(env, args[0], &handle) != napi_ok ||
        napi_get_arraybuffer_info(env, args[1], &source, &length) != napi_ok ||
        napi_get_value_int32(env, args[2], &stride) != napi_ok ||
        napi_get_value_bool(env, args[3], &bgra) != napi_ok) return Boolean(env, false);
    auto found = state->values.find(handle);
    if (found == state->values.end()) return Boolean(env, false);
    const Surface &surface = found->second;
    if (stride < surface.width * 4 || length < static_cast<size_t>(stride) * surface.height) return Boolean(env, false);
    OHNativeWindowBuffer *windowBuffer = nullptr;
    int fence = -1;
    if (OH_NativeWindow_NativeWindowRequestBuffer(surface.window, &windowBuffer, &fence) != 0) return Boolean(env, false);
    bool ready = true;
    if (fence >= 0) {
        pollfd descriptor {fence, POLLIN, 0};
        ready = poll(&descriptor, 1, 100) > 0 && !(descriptor.revents & (POLLERR | POLLNVAL));
        close(fence);
    }
    OH_NativeBuffer *buffer = nullptr;
    void *destination = nullptr;
    if (ready && OH_NativeBuffer_FromNativeWindowBuffer(windowBuffer, &buffer) == 0 &&
        OH_NativeBuffer_Map(buffer, &destination) == 0) {
        OH_NativeBuffer_Config config {};
        OH_NativeBuffer_GetConfig(buffer, &config);
        if (config.stride >= surface.width * 4 && config.height >= surface.height &&
            config.format == NATIVEBUFFER_PIXEL_FMT_RGBA_8888) {
            for (int y = 0; y < surface.height; y++) {
                const auto *src = static_cast<const uint8_t *>(source) + y * stride;
                auto *dst = static_cast<uint8_t *>(destination) + y * config.stride;
                if (!bgra) memcpy(dst, src, surface.width * 4);
                else for (int x = 0; x < surface.width; x++) {
                    dst[4*x] = src[4*x+2]; dst[4*x+1] = src[4*x+1];
                    dst[4*x+2] = src[4*x]; dst[4*x+3] = src[4*x+3];
                }
            }
            success = true;
        }
        OH_NativeBuffer_Unmap(buffer);
    }
    if (success) {
        timespec now {};
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t ns = static_cast<uint64_t>(now.tv_sec) * 1000000000 + now.tv_nsec;
        OH_NativeWindow_NativeWindowHandleOpt(surface.window, SET_UI_TIMESTAMP, ns);
        Region region {nullptr, 0};
        success = OH_NativeWindow_NativeWindowFlushBuffer(surface.window, windowBuffer, -1, region) == 0;
    }
    if (!success) OH_NativeWindow_NativeWindowAbortBuffer(surface.window, windowBuffer);
    return Boolean(env, success);
}
napi_value CloseSurface(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    void *data = nullptr;
    napi_get_cb_info(env, info, &argc, args, nullptr, &data);
    auto *state = static_cast<Surfaces *>(data);
    int handle = 0;
    if (argc == 1 && napi_get_value_int32(env, args[0], &handle) == napi_ok) {
        auto found = state->values.find(handle);
        if (found != state->values.end()) {
            OH_NativeWindow_DestroyNativeWindow(found->second.window);
            state->values.erase(found);
        }
    }
    return Number(env, 0);
}
napi_value Init(napi_env env, napi_value exports) {
    auto *state = new Surfaces();
    napi_add_env_cleanup_hook(env, [](void *data) { delete static_cast<Surfaces *>(data); }, state);
    napi_property_descriptor properties[] = {
        {"createOutput", nullptr, CreateOutput, nullptr, nullptr, nullptr, napi_default, state},
        {"openSurface", nullptr, OpenSurface, nullptr, nullptr, nullptr, napi_default, state},
        {"writeFrame", nullptr, WriteFrame, nullptr, nullptr, nullptr, napi_default, state},
        {"closeSurface", nullptr, CloseSurface, nullptr, nullptr, nullptr, napi_default, state},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    return exports;
}
} // namespace
static napi_module module = {1, 0, nullptr, Init, "superplayer_recorder", nullptr, {0}};
extern "C" __attribute__((constructor)) void RegisterSuperPlayerRecorder() { napi_module_register(&module); }
