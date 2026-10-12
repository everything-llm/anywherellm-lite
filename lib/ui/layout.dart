import 'package:flutter/painting.dart';

abstract final class Sizes {
  /// The widest the chat's turns and composer are laid out.
  static const column = 720.0;

  /// The least height a pane in `MinHeight` is laid out at; shorter, it scrolls whole.
  static const panelMin = 360.0;

  /// A card's corners.
  static const card = 24.0;

  /// An alert's or a notice's corners, less round than a [card].
  static const notice = 20.0;

  /// The composer's corners.
  static const composer = 28.0;

  /// A row's corners in a list or a menu.
  static const row = 10.0;

  /// A button's or a field's corners.
  static const control = 16.0;

  /// A small button's corners, and a tab's or a title's press.
  static const small = 12.0;

  /// Around a phone page's cards, under its header.
  static const pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 24);

  /// The least height of a row in a card: a sheet's, a chat's or a document's.
  static const cardRow = 64.0;

  /// The least height of a page's row that opens something, as in Settings.
  static const navRow = 68.0;

  /// The least height of a source an answer cited, in the sheet that lists them.
  static const citedRow = 80.0;

  /// The least height of a row that only says something, or holds a switch.
  static const infoRow = 88.0;

  /// A one-line field's height.
  static const field = 52.0;
}
