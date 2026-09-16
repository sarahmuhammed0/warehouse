import 'package:flutter/widgets.dart';

/// Border-radius tokens. Kept modest — an enterprise data app (§2's design
/// direction explicitly rejects "overly rounded cute UI"), not a consumer
/// app; `lg` is the largest radius used anywhere, reserved for dialogs/
/// sheets, not everyday cards and inputs.
class AppRadius {
  AppRadius._();

  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double pill = 999;

  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}
