import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'settings/settings_pages.dart';
import 'state/notice.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/phone_page.dart';
import 'widgets/scroll_fades.dart';

/// A page of what the toolkit adds over the chat, such as Upcoming: its title under a round
/// Back, [action] at the end, and [body] below. It runs [read] once as it opens, so what it shows
/// is read afresh.
class ToolkitPageFrame extends StatefulWidget {
  const ToolkitPageFrame({
    super.key,
    required this.title,
    required this.read,
    required this.body,
    this.action,
  });

  final String title;

  /// Reads what the page shows, once the frame that opens it is done.
  final VoidCallback read;

  /// The header's round button, such as Upcoming's New task, or null for none.
  final Widget? action;
  final Widget body;

  @override
  State<ToolkitPageFrame> createState() => _ToolkitPageFrameState();
}

class _ToolkitPageFrameState extends State<ToolkitPageFrame> {
  @override
  void initState() {
    super.initState();
    widget.read();
  }

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ColoredBox(
      color: Tokens.of(context).bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: widget.title,
            back: 'Back to the chats',
            onBack: shell.closeToolkitPage,
            action: widget.action,
          ),
          Expanded(child: ScrollFades(child: widget.body)),
        ],
      ),
    );
  }
}

/// What a toolkit page shows before it has something to: why its read failed, with a way to the
/// Connection page, or Reading… while it reads.
class NotRead extends StatelessWidget {
  const NotRead(this.problem, {super.key});

  final Notice? problem;

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    if (problem == null) {
      return Text(
        'Reading…',
        style: Type.sans(14, color: Tokens.of(context).muted),
      );
    }
    final shell = AppScope.of(context).shell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AlertBox.notice(AlertKind.warn, problem),
        AppButton(
          'Open Connection',
          onPressed: () => shell
            ..closeToolkitPage()
            ..openSettings(SettingsPage.connection),
        ),
      ],
    );
  }
}
