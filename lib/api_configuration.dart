const _buildApiBaseUrl = String.fromEnvironment('RTS_API_BASE_URL');

String resolveApiBaseUrl([String buildValue = _buildApiBaseUrl]) {
  return buildValue.trim();
}
