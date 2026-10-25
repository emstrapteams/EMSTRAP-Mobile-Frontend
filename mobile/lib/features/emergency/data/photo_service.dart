import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class CapturedPhoto {
  const CapturedPhoto(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;

  /// The backend expects `imageUrl` as a data URL and uploads it to
  /// Cloudinary itself; the app never talks to Cloudinary.
  String toDataUrl() => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException();
}

/// Camera / gallery via the system picker. No CAMERA permission is declared:
/// the picker hands off to the camera app, which owns that permission.
class PhotoService {
  PhotoService([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Cloudinary's free-plan image limit is 10 MB. After downscaling to
  /// 1280 px at 70% quality a photo is usually well under 1 MB.
  static const maxBytes = 8 * 1024 * 1024;

  /// Returns null if the user cancelled.
  Future<CapturedPhoto?> pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 70,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw const PhotoTooLargeException();
    final isPng = file.name.toLowerCase().endsWith('.png');
    return CapturedPhoto(bytes, isPng ? 'image/png' : 'image/jpeg');
  }
}

final photoServiceProvider = Provider<PhotoService>((_) => PhotoService());
