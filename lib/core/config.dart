/// App configuration. Mirrors the web client's env: Hub base URL + default library endpoint.
class AppConfig {
  const AppConfig({required this.backendUrl, this.defaultLibraryUrl});

  final String backendUrl;
  final String? defaultLibraryUrl;

  static const AppConfig dev = AppConfig(
    backendUrl: 'http://localhost:8080',
    defaultLibraryUrl: 'http://localhost:8443',
  );
}
