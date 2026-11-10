import 'package:flutter/material.dart';
import 'data/app_state.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KonturApp());
}

class KonturApp extends StatefulWidget {
  const KonturApp({super.key});
  @override
  State<KonturApp> createState() => _KonturAppState();
}

class _KonturAppState extends State<KonturApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.init();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KonturSurvey',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: HomePage(state: state),
      );
}
