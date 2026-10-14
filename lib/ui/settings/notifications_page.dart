import 'package:flutter/material.dart';

import '../../core/push.dart';
import '../app_scope.dart';
import '../state/push_controller.dart';
import '../widgets/basics.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/radio_card.dart';
import 'rows.dart';

/// Push notifications on this device: the switch, the distributor to use when the device has
/// several, and where each source's notifications stand.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  static String _status(PushState? state) => switch (state?.status) {
    PushStatus.on => 'On',
    PushStatus.waiting || null => 'Starting',
    PushStatus.unavailable => 'Not available',
    PushStatus.failed => 'Failed',
  };

  @override
  Widget build(BuildContext context) {
    final push = AppScope.of(context).push!;
    return ListenableBuilder(
      listenable: push,
      builder: (context, _) {
        final on = push.on == true;
        final whys = [
          for (final source in PushSource.values)
            if (push.states[source]?.why case final why?)
              '${source.label}: $why',
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            FieldCard([
              FieldRow(
                label: 'Notifications',
                small: true,
                control: AppSwitch(
                  value: on,
                  label: 'Notifications',
                  onChanged: push.on == null
                      ? null
                      : (turnOn) => turnOn ? push.turnOn() : push.turnOff(),
                ),
              ),
            ]),
            if (push.choices case final choices?) ...[
              const CardHeading('Distributor', top: 8),
              for (final choice in choices)
                RadioCard(
                  title: distributorName(choice),
                  selected: false,
                  onTap: () => push.choose(choice),
                ),
            ],
            if (push.problem case final problem?)
              AlertBox(AlertKind.bad, 'Notifications stay off', text: problem),
            if (on) ...[
              const CardHeading('Sent by', top: 8),
              FieldCard([
                for (final source in PushSource.values)
                  InfoRow(source.label, about: _status(push.states[source])),
              ]),
              for (final why in whys) HelpText(why),
            ],
            const PageNote(
              'Notifications come through a UnifiedPush distributor, such as ntfy, installed on '
              'this phone. The apps server sends what each app asks to, to every device.',
            ),
          ],
        );
      },
    );
  }
}
