import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 5,
  // Avoid dart:io on web
  lineLength: 120,
  colors: !kIsWeb,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static Logger get i => _logger;
}
