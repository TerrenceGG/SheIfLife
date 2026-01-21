import 'package:flutter/material.dart';
import 'package:she_if_life/app.dart';
import 'package:she_if_life/db/local_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.init();
  runApp(const AppRoot());
}