abstract final class Sizes {
  /// The widest the chat's turns and composer are laid out.
  static const column = 720.0;

  /// The least height a pane in `MinHeight` is laid out at; shorter, it scrolls whole.
  static const panelMin = 360.0;

  /// A card's or a panel's corners.
  static const card = 20.0;

  /// A grouped card's corners, rounder than [card].
  static const phoneCard = 24.0;

  /// The composer's corners.
  static const phoneComposer = 28.0;

  /// A row's corners in a list or a menu.
  static const row = 10.0;
  static const control = 12.0;

  /// A button's or a field's corners, rounder than [control].
  static const phoneControl = 16.0;

  /// A one-line field's height.
  static const field = 52.0;
}
