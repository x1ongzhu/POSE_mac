#include <SDL.h>
#include <SDL_image.h>

#include <memory>
#include <optional>
#include <string>
#include <cstring>
#include <fstream>

#include "EmDevice.h"
#include "EmSession.h"
#include "EmSystemState.h"
#include "ButtonEvent.h"
#include "DbInstaller.h"
#include "ExternalStorage.h"
#include "CardImage.h"
#include "Feature.h"
#include "MainLoop.h"
#include "PenEvent.h"
#include "ProxyHandler.h"
#include "ScreenDimensions.h"
#include "SessionImage.h"
#include "proxyClientNative.h"
#include "util.h"

namespace {
SDL_Surface* surface = nullptr;
SDL_Renderer* renderer = nullptr;
std::unique_ptr<MainLoop> loop;
std::unique_ptr<ProxyClient> proxyClient;
std::unique_ptr<ProxyHandler> proxyHandler;
std::string error;
std::string detectedDevice;
}

extern "C" const char* cloudpilot_embedded_detect_device(const char* rom) {
    detectedDevice.clear();
    if (!rom) return nullptr;

    std::unique_ptr<uint8[]> data;
    size_t size = 0;
    if (!util::ReadFile(rom, data, size)) return nullptr;

    SessionImage sessionImage;
    if (sessionImage.Deserialize(data.get(), size)) {
        detectedDevice = sessionImage.GetDeviceId();
        return detectedDevice.empty() ? nullptr : detectedDevice.c_str();
    }

    EmROMReader reader(data.get(), size);
    if (!reader.Read()) return nullptr;

    for (const char* id : util::SUPPORTED_DEVICES) {
        EmDevice device(id);
        if (device.SupportsROM(reader)) {
            detectedDevice = id;
            return detectedDevice.c_str();
        }
    }
    return nullptr;
}

extern "C" int cloudpilot_embedded_install_database(const char* path) {
    if (!loop || !path) return static_cast<int>(DbInstaller::Result::failureUnknownReason);
    std::unique_ptr<uint8[]> data;
    size_t size = 0;
    if (!util::ReadFile(path, data, size))
        return static_cast<int>(DbInstaller::Result::failureUnknownReason);
    return static_cast<int>(DbInstaller(size, data.get()).Install());
}

extern "C" bool cloudpilot_embedded_launch_app_for_database(const char* path) {
    if (!loop || !path) return false;
    std::unique_ptr<uint8[]> data;
    size_t size = 0;
    if (!util::ReadFile(path, data, size) || size < 64 ||
        std::memcmp(data.get() + 60, "appl", 4) != 0) return false;

    const char* name = reinterpret_cast<const char*>(data.get());
    const void* terminator = std::memchr(name, '\0', 32);
    if (!terminator || name[0] == '\0') return false;
    return gSession->LaunchAppByName(std::string(name));
}

extern "C" bool cloudpilot_embedded_mount_card(const char* path) {
    return loop && path && util::mountImage(path);
}

extern "C" bool cloudpilot_embedded_save_card(const char* path) {
    if (!loop || !path) return false;
    EmHAL::Slot slot = util::mountedSlot();
    if (slot == EmHAL::Slot::none) return false;
    CardImage* image = gExternalStorage.GetImageInSlot(slot);
    if (!image) return false;
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) return false;
    stream.write(reinterpret_cast<const char*>(image->RawData()),
                 image->BlocksTotal() * CardImage::BLOCK_SIZE);
    return stream.good();
}

extern "C" bool cloudpilot_embedded_unmount_card() {
    if (!loop) return false;
    EmHAL::Slot slot = util::mountedSlot();
    if (slot == EmHAL::Slot::none) return false;
    return gExternalStorage.RemoveImage(gExternalStorage.GetImageKeyInSlot(slot));
}

extern "C" const char* cloudpilot_embedded_start(const char* rom, const char* device,
                                                   void*) {
    if (loop) return "The emulator is already running";
    if (!rom || !device) return "Missing ROM or device";

    if (!util::initializeSession(rom, std::string(device)))
        return "Unable to initialize the selected ROM and device";

    SDL_setenv("SDL_VIDEODRIVER", "dummy", 1);
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        error = SDL_GetError();
        return error.c_str();
    }
    IMG_Init(IMG_INIT_PNG);
    SDL_StartTextInput();

    const ScreenDimensions dimensions(gSession->GetDevice().GetScreenDimensions());
    const int scale = 2;
    surface = SDL_CreateRGBSurfaceWithFormat(0, dimensions.Width() * scale,
                    (dimensions.Height() + dimensions.SilkscreenHeight()) * scale,
                    32, SDL_PIXELFORMAT_ARGB8888);
    if (!surface) {
        error = SDL_GetError();
        SDL_Quit();
        return error.c_str();
    }
    renderer = SDL_CreateSoftwareRenderer(surface);
    if (!renderer) {
        error = SDL_GetError();
        SDL_FreeSurface(surface);
        surface = nullptr;
        SDL_Quit();
        return error.c_str();
    }

    Feature::SetClipboardIntegration(true);
    loop = std::make_unique<MainLoop>(nullptr, renderer, scale);
    proxyClient.reset(proxyClientNative::Create());
    proxyHandler = std::make_unique<ProxyHandler>(*proxyClient);
    proxyHandler->Initialize();
    Feature::SetNetworkRedirection(true);
    return nullptr;
}

extern "C" void cloudpilot_embedded_set_network(bool enabled) {
    Feature::SetNetworkRedirection(enabled && proxyHandler != nullptr);
}

extern "C" bool cloudpilot_embedded_ui_ready() {
    return loop && gSystemState.IsUIInitialized();
}

extern "C" bool cloudpilot_embedded_cycle() {
    if (!loop) return false;
    loop->Cycle();
    if (proxyHandler) proxyHandler->HandleSuspend();
    return loop->IsRunning();
}

extern "C" void cloudpilot_embedded_size(int* width, int* height, int* pitch) {
    if (!surface) return;
    if (width) *width = surface->w;
    if (height) *height = surface->h;
    if (pitch) *pitch = surface->pitch;
}

extern "C" bool cloudpilot_embedded_copy_frame(void* destination, size_t length) {
    if (!surface || !destination || length < static_cast<size_t>(surface->pitch * surface->h))
        return false;
    std::memcpy(destination, surface->pixels, surface->pitch * surface->h);
    return true;
}

extern "C" void cloudpilot_embedded_pen(int x, int y, bool down) {
    if (!loop) return;
    if (down) gSession->QueuePenEvent(PenEvent::down(x / 2, y / 2));
    else gSession->QueuePenEvent(PenEvent::up());
}

extern "C" void cloudpilot_embedded_key(int key) {
    if (loop) gSession->QueueKeyboardEvent(key);
}

extern "C" void cloudpilot_embedded_button(int button, bool down) {
    if (!loop || button < 0 || button > 7) return;
    gSession->QueueButtonEvent(ButtonEvent(
        static_cast<ButtonEvent::Button>(button),
        down ? ButtonEvent::Type::press : ButtonEvent::Type::release));
}

extern "C" void cloudpilot_embedded_reset() {
    if (loop) gSession->Reset(EmSession::ResetType::soft);
}

extern "C" bool cloudpilot_embedded_save(const char* path) {
    if (!loop || !path) return false;
    SessionImage image;
    if (!gSession->SaveImage(image)) return false;
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) return false;
    stream.write(static_cast<const char*>(image.GetSerializedImage()),
                 image.GetSerializedImageSize());
    return stream.good();
}

extern "C" void cloudpilot_embedded_stop() {
    Feature::SetNetworkRedirection(false);
    if (proxyHandler) proxyHandler->Teardown();
    proxyHandler.reset();
    proxyClient.reset();
    loop.reset();
    if (renderer) SDL_DestroyRenderer(renderer);
    if (surface) SDL_FreeSurface(surface);
    renderer = nullptr;
    surface = nullptr;
    IMG_Quit();
    SDL_Quit();
}
