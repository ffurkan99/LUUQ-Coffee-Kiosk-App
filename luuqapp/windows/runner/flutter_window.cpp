#include "flutter_window.h"

#include <mmsystem.h>
#include <optional>
#include <string>
#include <windows.h>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "winmm.lib")

namespace {

std::wstring GetSoundAssetPath(const wchar_t* file_name) {
  wchar_t executable_path[MAX_PATH];
  GetModuleFileNameW(nullptr, executable_path, MAX_PATH);

  std::wstring path(executable_path);
  const size_t last_separator = path.find_last_of(L"\\/");
  if (last_separator != std::wstring::npos) {
    path.erase(last_separator + 1);
  }

  path.append(L"data\\flutter_assets\\assets\\sounds\\");
  path.append(file_name);
  return path;
}

std::wstring GetWheelTickSoundPath() {
  return GetSoundAssetPath(L"wheel_tick.wav");
}

std::wstring GetResultSoundPath() {
  return GetSoundAssetPath(L"result_chime.wav");
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  spin_sound_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "luuqapp/spin_sound",
          &flutter::StandardMethodCodec::GetInstance());
  spin_sound_channel_->SetMethodCallHandler(
      [tick_sound_path = GetWheelTickSoundPath(),
       result_sound_path = GetResultSoundPath()](
          const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "tick") {
          double volume = 1.0;
          if (call.arguments()) {
            const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
            if (arguments) {
              auto vol_it = arguments->find(flutter::EncodableValue("volume"));
              if (vol_it != arguments->end() && !vol_it->second.IsNull()) {
                if (std::holds_alternative<double>(vol_it->second)) {
                  volume = std::get<double>(vol_it->second);
                } else if (std::holds_alternative<int32_t>(vol_it->second)) {
                  volume = static_cast<double>(std::get<int32_t>(vol_it->second));
                } else if (std::holds_alternative<int64_t>(vol_it->second)) {
                  volume = static_cast<double>(std::get<int64_t>(vol_it->second));
                }
              }
            }
          }
          WORD volWord = static_cast<WORD>(volume * 0xFFFF);
          DWORD dwVol = (volWord << 16) | volWord;
          if (waveOutSetVolume(reinterpret_cast<HWAVEOUT>(static_cast<DWORD_PTR>(WAVE_MAPPER)), dwVol) != MMSYSERR_NOERROR) {
            waveOutSetVolume(0, dwVol);
          }

          PlaySoundW(nullptr, nullptr, SND_PURGE);
          PlaySoundW(tick_sound_path.c_str(), nullptr,
                     SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
          result->Success();
          return;
        }
        if (call.method_name() == "result") {
          double volume = 0.65;
          if (call.arguments()) {
            const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
            if (arguments) {
              auto vol_it = arguments->find(flutter::EncodableValue("volume"));
              if (vol_it != arguments->end() && !vol_it->second.IsNull()) {
                if (std::holds_alternative<double>(vol_it->second)) {
                  volume = std::get<double>(vol_it->second);
                } else if (std::holds_alternative<int32_t>(vol_it->second)) {
                  volume = static_cast<double>(std::get<int32_t>(vol_it->second));
                } else if (std::holds_alternative<int64_t>(vol_it->second)) {
                  volume = static_cast<double>(std::get<int64_t>(vol_it->second));
                }
              }
            }
          }
          WORD volWord = static_cast<WORD>(volume * 0xFFFF);
          DWORD dwVol = (volWord << 16) | volWord;
          if (waveOutSetVolume(reinterpret_cast<HWAVEOUT>(static_cast<DWORD_PTR>(WAVE_MAPPER)), dwVol) != MMSYSERR_NOERROR) {
            waveOutSetVolume(0, dwVol);
          }

          PlaySoundW(result_sound_path.c_str(), nullptr,
                     SND_FILENAME | SND_ASYNC | SND_NODEFAULT);
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  spin_sound_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
