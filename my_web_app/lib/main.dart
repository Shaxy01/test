import 'package:flutter/material.dart';
import 'main.dart';  // Import głównego pliku aplikacji

void main() {
  runApp(MyAppWeb());
}

class MyAppWeb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Wykorzystuje główną logikę aplikacji z main.dart
    return MyApp();
  }
}
