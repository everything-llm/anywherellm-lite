import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';

/// The [CodeScanner] the app uses on Android: the back camera, reading QR codes only.
/// A camera that cannot start says why in its place.
Widget cameraScanner(void Function(String code) onCode) =>
    _CameraScanner(onCode: onCode);

class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.onCode});

  final void Function(String code) onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Hands on the first code read, once.
  void _detect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue case final code?) {
        _done = true;
        widget.onCode(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: AspectRatio(
        aspectRatio: 1,
        child: MobileScanner(
          controller: _controller,
          onDetect: _detect,
          errorBuilder: (context, error) => ColoredBox(
            color: t.tile,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _plain(error),
                  textAlign: TextAlign.center,
                  style: Type.sans(12.5, color: t.muted, height: 1.45),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What went wrong with the camera, in plain words.
String _plain(MobileScannerException error) => switch (error.errorCode) {
  MobileScannerErrorCode.permissionDenied => "AnywhereLLM needs the camera to scan the code. Allow it in Android's settings for the app.",
  MobileScannerErrorCode.unsupported =>
    'This device has no camera that can scan.',
  _ => 'The camera could not start. Type the address and key instead.',
};
