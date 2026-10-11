import 'package:image_picker/image_picker.dart';

import 'photo_picker.dart';

/// [PhotoPicker] through `image_picker`: the system's photo picker and its camera app.
class DevicePhotos implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<List<XFile>> choose() => _picker.pickMultiImage();

  @override
  Future<XFile?> take() => _picker.pickImage(source: ImageSource.camera);
}
