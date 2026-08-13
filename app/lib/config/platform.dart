import 'dart:io' show Platform;

/// Shared platform flags for the desktop (Windows / Linux, and macOS
/// if it returns) port. Keep this file free of Flutter widgets so
/// ViewModels and data services can import it without pulling UI.
bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
