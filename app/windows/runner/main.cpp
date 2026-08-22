#include <windows.h>
#include <iostream>
#include <fstream>
#include <filesystem>

#include "flutter_window.h"
#include "utils.h"

static std::ofstream g_log;

void Log(const std::string& msg) {
  if (g_log.is_open()) {
    g_log << msg << std::endl;
    g_log.flush();
  }
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  try {
    auto temp_path = std::filesystem::temp_directory_path() / "remote_pi_debug.log";
    g_log.open(temp_path, std::ios::out | std::ios::trunc);
  } catch (...) {}
  Log("[Runner] wWinMain entered");

  HANDLE hMutex = ::CreateMutexW(nullptr, TRUE, L"Local\\RemotePi_SingleInstance_Mutex_App");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    Log("[Runner] Another instance already running, focusing existing window");
    HWND existingHwnd = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Remote Pi");
    if (existingHwnd) {
      ::ShowWindow(existingHwnd, SW_RESTORE);
      ::SetForegroundWindow(existingHwnd);
    }
    if (hMutex) ::CloseHandle(hMutex);
    return EXIT_SUCCESS;
  }

  if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
    FILE *unused;
    freopen_s(&unused, "CONOUT$", "w", stdout);
    freopen_s(&unused, "CONOUT$", "w", stderr);
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  } else if (::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  wchar_t exe_buffer[MAX_PATH];
  ::GetModuleFileNameW(nullptr, exe_buffer, MAX_PATH);
  std::filesystem::path exe_path(exe_buffer);
  std::filesystem::path data_path = exe_path.parent_path() / "data";
  Log("[Runner] data_path: " + data_path.string());

  flutter::DartProject project(data_path.wstring());

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  Log("[Runner] Creating FlutterWindow");
  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Remote Pi", origin, size)) {
    Log("[Runner] window.Create failed!");
    return EXIT_FAILURE;
  }
  Log("[Runner] window.Create succeeded");
  window.SetQuitOnClose(true);
  window.Show();

  Log("[Runner] Entering message loop");
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  Log("[Runner] Message loop exited with msg.wParam=" + std::to_string(msg.wParam));
  if (hMutex) {
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
