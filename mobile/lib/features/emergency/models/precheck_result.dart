import 'emergency_request.dart';

/// Result of `POST /api/emergency/precheck`: the photo has been uploaded
/// (Cloudinary, server-side) and, when AI is enabled, classified.
class PrecheckResult {
  const PrecheckResult({
    required this.secureImageUrl,
    required this.aiAvailable,
    this.aiAnalysis,
    this.warningRequired = false,
  });

  final String secureImageUrl;

  /// False when the backend answered 503 "AI service is currently disabled".
  /// The photo upload still succeeded in that case.
  final bool aiAvailable;
  final AiAnalysis? aiAnalysis;

  /// The backend sets this when AI confidence is below 60%.
  final bool warningRequired;
}
