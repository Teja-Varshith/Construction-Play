import 'package:flutter/material.dart';

import '../../../core/widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: LoadingView(message: 'Loading…'));
}
