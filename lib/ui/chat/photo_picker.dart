import 'package:cross_file/cross_file.dart';

/// Pictures for the composer from the device's own photos and camera.
abstract interface class PhotoPicker {
  /// The pictures chosen from the photo library, none when the person cancels.
  Future<List<XFile>> choose();

  /// A photo taken with the camera, or null when the person cancels. Throws when the camera
  /// cannot be used, as when its permission is refused.
  Future<XFile?> take();
}
