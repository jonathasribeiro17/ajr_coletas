import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionText extends StatefulWidget {
  const AppVersionText({super.key});

  @override
  State<AppVersionText> createState() => _AppVersionTextState();
}

class _AppVersionTextState extends State<AppVersionText> {
  String _versao = '';

  @override
  void initState() {
    super.initState();
    _carregarVersao();
  }

  Future<void> _carregarVersao() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;

    setState(() {
      _versao = 'Versão ${info.version} (${info.buildNumber})';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _versao,
      style: const TextStyle(
        fontSize: 11,
        color: Colors.grey,
      ),
    );
  }
}
