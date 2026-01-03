#include <napi.h>
#include <thread>
#include <mutex>
#include <queue>
#include <atomic>
#include "audiotee_bridge.h"

// Forward declarations
class AudioTeeWrapper;

// Thread-safe queue for events
struct AudioEvent {
    int32_t type;          // 0=data, 1=start, 2=stop, 3=error, 4=metadata
    std::vector<uint8_t> data;
    std::string message;
    double sampleRate;
    uint32_t channelsPerFrame;
    uint32_t bitsPerChannel;
    bool isFloat;
    std::string encoding;
};

class AudioTeeWrapper : public Napi::ObjectWrap<AudioTeeWrapper> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports);
    AudioTeeWrapper(const Napi::CallbackInfo& info);
    ~AudioTeeWrapper();

private:
    static Napi::FunctionReference constructor;

    // Instance methods
    Napi::Value Start(const Napi::CallbackInfo& info);
    Napi::Value Stop(const Napi::CallbackInfo& info);
    Napi::Value IsRunning(const Napi::CallbackInfo& info);
    Napi::Value ProcessEvents(const Napi::CallbackInfo& info);

    // Callbacks from Swift
    static void OnData(const uint8_t* data, int32_t length, void* context);
    static void OnEvent(int32_t eventType, const char* message, void* context);
    static void OnMetadata(double sampleRate, uint32_t channelsPerFrame,
                          uint32_t bitsPerChannel, bool isFloat,
                          const char* encoding, void* context);

    // Queue management
    void QueueEvent(AudioEvent event);
    std::vector<AudioEvent> DrainEvents();

    AudioTeeHandle handle_;
    std::mutex eventMutex_;
    std::queue<AudioEvent> eventQueue_;
    std::atomic<bool> isDestroyed_{false};
};

Napi::FunctionReference AudioTeeWrapper::constructor;

Napi::Object AudioTeeWrapper::Init(Napi::Env env, Napi::Object exports) {
    Napi::HandleScope scope(env);

    Napi::Function func = DefineClass(env, "AudioTeeNative", {
        InstanceMethod("start", &AudioTeeWrapper::Start),
        InstanceMethod("stop", &AudioTeeWrapper::Stop),
        InstanceMethod("isRunning", &AudioTeeWrapper::IsRunning),
        InstanceMethod("processEvents", &AudioTeeWrapper::ProcessEvents),
    });

    constructor = Napi::Persistent(func);
    constructor.SuppressDestruct();

    exports.Set("AudioTeeNative", func);
    return exports;
}

AudioTeeWrapper::AudioTeeWrapper(const Napi::CallbackInfo& info)
    : Napi::ObjectWrap<AudioTeeWrapper>(info) {
    Napi::Env env = info.Env();

    handle_ = audiotee_create(
        &AudioTeeWrapper::OnData,
        &AudioTeeWrapper::OnEvent,
        &AudioTeeWrapper::OnMetadata,
        this
    );

    if (!handle_) {
        Napi::Error::New(env, "Failed to create AudioTee session").ThrowAsJavaScriptException();
    }
}

AudioTeeWrapper::~AudioTeeWrapper() {
    isDestroyed_ = true;
    if (handle_) {
        audiotee_destroy(handle_);
        handle_ = nullptr;
    }
}

Napi::Value AudioTeeWrapper::Start(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsObject()) {
        Napi::TypeError::New(env, "Options object expected").ThrowAsJavaScriptException();
        return env.Null();
    }

    Napi::Object options = info[0].As<Napi::Object>();

    // Extract options with defaults
    double sampleRate = 0;
    if (options.Has("sampleRate") && options.Get("sampleRate").IsNumber()) {
        sampleRate = options.Get("sampleRate").As<Napi::Number>().DoubleValue();
    }

    double chunkDurationMs = 200;
    if (options.Has("chunkDurationMs") && options.Get("chunkDurationMs").IsNumber()) {
        chunkDurationMs = options.Get("chunkDurationMs").As<Napi::Number>().DoubleValue();
    }

    bool mute = false;
    if (options.Has("mute") && options.Get("mute").IsBoolean()) {
        mute = options.Get("mute").As<Napi::Boolean>().Value();
    }

    bool isMono = true;
    if (options.Has("stereo") && options.Get("stereo").IsBoolean()) {
        isMono = !options.Get("stereo").As<Napi::Boolean>().Value();
    }

    // Handle process arrays
    std::vector<int32_t> includeProcesses;
    std::vector<int32_t> excludeProcesses;

    if (options.Has("includeProcesses") && options.Get("includeProcesses").IsArray()) {
        Napi::Array arr = options.Get("includeProcesses").As<Napi::Array>();
        for (uint32_t i = 0; i < arr.Length(); i++) {
            if (arr.Get(i).IsNumber()) {
                includeProcesses.push_back(arr.Get(i).As<Napi::Number>().Int32Value());
            }
        }
    }

    if (options.Has("excludeProcesses") && options.Get("excludeProcesses").IsArray()) {
        Napi::Array arr = options.Get("excludeProcesses").As<Napi::Array>();
        for (uint32_t i = 0; i < arr.Length(); i++) {
            if (arr.Get(i).IsNumber()) {
                excludeProcesses.push_back(arr.Get(i).As<Napi::Number>().Int32Value());
            }
        }
    }

    int32_t result = audiotee_start(
        handle_,
        sampleRate,
        chunkDurationMs,
        mute,
        isMono,
        includeProcesses.empty() ? nullptr : includeProcesses.data(),
        static_cast<int32_t>(includeProcesses.size()),
        excludeProcesses.empty() ? nullptr : excludeProcesses.data(),
        static_cast<int32_t>(excludeProcesses.size())
    );

    if (result != 0) {
        std::string errorMsg = "Failed to start AudioTee: error code " + std::to_string(result);
        Napi::Error::New(env, errorMsg).ThrowAsJavaScriptException();
        return env.Null();
    }

    return env.Undefined();
}

Napi::Value AudioTeeWrapper::Stop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    int32_t result = audiotee_stop(handle_);
    if (result != 0) {
        Napi::Error::New(env, "Failed to stop AudioTee").ThrowAsJavaScriptException();
    }

    return env.Undefined();
}

Napi::Value AudioTeeWrapper::IsRunning(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), audiotee_is_running(handle_));
}

Napi::Value AudioTeeWrapper::ProcessEvents(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    std::vector<AudioEvent> events = DrainEvents();
    Napi::Array result = Napi::Array::New(env, events.size());

    for (size_t i = 0; i < events.size(); i++) {
        const AudioEvent& event = events[i];
        Napi::Object obj = Napi::Object::New(env);

        obj.Set("type", Napi::Number::New(env, event.type));

        switch (event.type) {
            case 0: // data
                {
                    Napi::Buffer<uint8_t> buffer = Napi::Buffer<uint8_t>::Copy(
                        env, event.data.data(), event.data.size()
                    );
                    obj.Set("data", buffer);
                }
                break;

            case 1: // start
            case 2: // stop
                // No additional data needed
                break;

            case 3: // error
                obj.Set("message", Napi::String::New(env, event.message));
                break;

            case 4: // metadata
                obj.Set("sampleRate", Napi::Number::New(env, event.sampleRate));
                obj.Set("channelsPerFrame", Napi::Number::New(env, event.channelsPerFrame));
                obj.Set("bitsPerChannel", Napi::Number::New(env, event.bitsPerChannel));
                obj.Set("isFloat", Napi::Boolean::New(env, event.isFloat));
                obj.Set("encoding", Napi::String::New(env, event.encoding));
                break;
        }

        result.Set(i, obj);
    }

    return result;
}

void AudioTeeWrapper::OnData(const uint8_t* data, int32_t length, void* context) {
    AudioTeeWrapper* self = static_cast<AudioTeeWrapper*>(context);
    if (self->isDestroyed_) return;

    AudioEvent event;
    event.type = 0;
    event.data.assign(data, data + length);
    self->QueueEvent(std::move(event));
}

void AudioTeeWrapper::OnEvent(int32_t eventType, const char* message, void* context) {
    AudioTeeWrapper* self = static_cast<AudioTeeWrapper*>(context);
    if (self->isDestroyed_) return;

    AudioEvent event;
    // eventType from Swift: 0=start, 1=stop, 2=error
    // We remap: 1=start, 2=stop, 3=error (0 is reserved for data)
    event.type = eventType + 1;
    if (message) {
        event.message = message;
    }
    self->QueueEvent(std::move(event));
}

void AudioTeeWrapper::OnMetadata(double sampleRate, uint32_t channelsPerFrame,
                                  uint32_t bitsPerChannel, bool isFloat,
                                  const char* encoding, void* context) {
    AudioTeeWrapper* self = static_cast<AudioTeeWrapper*>(context);
    if (self->isDestroyed_) return;

    AudioEvent event;
    event.type = 4;
    event.sampleRate = sampleRate;
    event.channelsPerFrame = channelsPerFrame;
    event.bitsPerChannel = bitsPerChannel;
    event.isFloat = isFloat;
    event.encoding = encoding ? encoding : "";
    self->QueueEvent(std::move(event));
}

void AudioTeeWrapper::QueueEvent(AudioEvent event) {
    std::lock_guard<std::mutex> lock(eventMutex_);
    eventQueue_.push(std::move(event));
}

std::vector<AudioEvent> AudioTeeWrapper::DrainEvents() {
    std::lock_guard<std::mutex> lock(eventMutex_);
    std::vector<AudioEvent> events;
    while (!eventQueue_.empty()) {
        events.push_back(std::move(eventQueue_.front()));
        eventQueue_.pop();
    }
    return events;
}

// Permission API - static functions

Napi::Value GetPermissionStatus(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    int32_t status = audiotee_permission_status();

    std::string statusStr;
    switch (status) {
        case 0: statusStr = "unknown"; break;
        case 1: statusStr = "denied"; break;
        case 2: statusStr = "authorized"; break;
        default: statusStr = "unknown"; break;
    }

    return Napi::String::New(env, statusStr);
}

Napi::Value IsPermissionAvailable(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), audiotee_permission_available());
}

Napi::Value OpenSystemSettings(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), audiotee_open_system_settings());
}

// Thread-safe function for permission request callback
struct PermissionRequestContext {
    Napi::ThreadSafeFunction tsfn;
};

void PermissionRequestCallback(bool granted, void* context) {
    auto* ctx = static_cast<PermissionRequestContext*>(context);

    ctx->tsfn.BlockingCall([granted](Napi::Env env, Napi::Function callback) {
        callback.Call({Napi::Boolean::New(env, granted)});
    });

    ctx->tsfn.Release();
    delete ctx;
}

Napi::Value RequestPermission(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (info.Length() < 1 || !info[0].IsFunction()) {
        Napi::TypeError::New(env, "Callback function expected").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    Napi::Function callback = info[0].As<Napi::Function>();

    auto* ctx = new PermissionRequestContext();
    ctx->tsfn = Napi::ThreadSafeFunction::New(
        env,
        callback,
        "PermissionCallback",
        0,
        1
    );

    audiotee_permission_request(PermissionRequestCallback, ctx);

    return env.Undefined();
}

// Module initialization
Napi::Object Init(Napi::Env env, Napi::Object exports) {
    AudioTeeWrapper::Init(env, exports);

    // Add permission functions
    exports.Set("getPermissionStatus", Napi::Function::New(env, GetPermissionStatus));
    exports.Set("isPermissionAvailable", Napi::Function::New(env, IsPermissionAvailable));
    exports.Set("requestPermission", Napi::Function::New(env, RequestPermission));
    exports.Set("openSystemSettings", Napi::Function::New(env, OpenSystemSettings));

    return exports;
}

NODE_API_MODULE(audiotee, Init)
