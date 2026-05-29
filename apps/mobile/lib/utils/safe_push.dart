import 'package:flutter/widgets.dart';

/// Pushes [route] only when [context]'s current route is still the top-most
/// one. This rejects the second tap of an accidental double-tap that would
/// otherwise stack two identical screens. Returns the route's result, or null
/// when the push was skipped.
Future<T?> pushRouteOnce<T>(BuildContext context, Route<T> route) {
  if (ModalRoute.of(context)?.isCurrent != true) {
    return Future<T?>.value();
  }
  return Navigator.of(context).push(route);
}
