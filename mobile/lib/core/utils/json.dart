/// Small helpers for reading backend JSON without passing raw maps around.
library;

Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw const FormatException('Expected a JSON object');
}

List<Map<String, dynamic>> asJsonList(Object? value) {
  if (value is! List) throw const FormatException('Expected a JSON array');
  return value.map(asJsonMap).toList();
}

String requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing "$key"');
}

String? optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

double? optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toDouble() : null;
}

DateTime? optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

/// Mongo references arrive either as an id string or as a populated object.
String? refId(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is Map && value['_id'] is String) return value['_id'] as String;
  return null;
}
