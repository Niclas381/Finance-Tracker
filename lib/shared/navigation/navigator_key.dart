import 'package:flutter/material.dart';

/// Globaler NavigatorKey, mit dem sich aus Services / Hintergrund-Callbacks
/// Routen pushen lassen, ohne einen BuildContext zu haben.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
