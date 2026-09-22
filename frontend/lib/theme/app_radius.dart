import 'package:flutter/widgets.dart';

/// Border-radius tokens.
///
/// The FactoryOS surface language is built on generously rounded white
/// panels, so the scale is anchored on [card] (the radius of every content
/// surface) rather than on a small "default". The smaller steps exist for
/// things that sit *inside* a card — an icon chip, an input, a bar in a
/// chart — where repeating the card's own radius would read as a second
/// card rather than as content.
class AppRadius {
  AppRadius._();

  /// Chart bars, small inline chips, table cell affordances.
  static const double xs = 6;

  /// Icon chips, status wells, anything nested two levels deep.
  static const double sm = 10;

  /// Inputs, buttons that aren't pills, menus.
  static const double md = 14;

  /// Nested panels inside a card (the grey well behind a sub-list).
  static const double lg = 16;

  /// The standard content surface: cards, tables, the shell's bars.
  static const double card = 20;

  /// Dialogs and sheets — one step above a card so an overlay reads as
  /// floating above the page rather than as another panel on it.
  static const double xl = 24;

  static const double pill = 999;

  static const BorderRadius xsRadius = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}
