import 'package:image_picker/image_picker.dart';

import 'photo_picker.dart';

/// [PhotoPicker] through `image_picker`: the system's photo picker and its camera app. Each
/// picture comes at most [_longest] px wide, at JPEG quality [_quality], as a model reads no
/// more and a camera's full size would cost the upload.
class DevicePhotos implements PhotoPicker {
  final _picker = ImagePicker();

  static const _longest = 2048.0;
  static const _quality = 85;

  @override
  Future<List<XFile>> choose() =>
      _picker.pickMultiImage(maxWidth: _longest, imageQuality: _quality);

  @override
  Future<XFile?> take() => _picker.pickImage(
    source: ImageSource.camera,
    maxWidth: _longest,
    imageQuality: _quality,
  );
}
