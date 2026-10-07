import 'package:flutter/material.dart';

import '../../core/connection.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/qr_mark.dart';

/// [connection] as a QR code a phone scans in its own Settings, with why the phone cannot use it
/// when it cannot.
class PairingCode extends StatelessWidget {
  const PairingCode(this.connection, {super.key});

  final Connection connection;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrMark(
                pairingCode(connection),
                label: 'QR code with the server address and key',
              ),
            ),
          ),
        ),
        Text(
          'Anyone who sees this code can use your key. Scan it in AnywhereLLM on your phone: '
          'Settings, Scan QR code.',
          style: Type.sans(12.5, color: t.muted, height: 1.45),
        ),
        if (pairingProblem(connection) case final problem?)
          AlertBox(
            AlertKind.warn,
            'Your phone cannot use this address',
            text: problem,
          ),
      ],
    );
  }
}
