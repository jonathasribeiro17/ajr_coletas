import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CanhotoFotoResultado {
  final String caminho;
  final bool removerArquivoOrigem;

  const CanhotoFotoResultado({
    required this.caminho,
    required this.removerArquivoOrigem,
  });
}

class CanhotoCameraScreen extends StatefulWidget {
  final String numeroNfe;

  const CanhotoCameraScreen({
    super.key,
    required this.numeroNfe,
  });

  @override
  State<CanhotoCameraScreen> createState() =>
      _CanhotoCameraScreenState();
}

class _CanhotoCameraScreenState
    extends State<CanhotoCameraScreen> {
  CameraController? _controller;

  bool _inicializando = true;
  bool _capturando = false;
  String? _erro;
  String? _fotoTemporariaPath;
  bool _fotoDaGaleria = false;

  bool get _emPreview => _fotoTemporariaPath != null;

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    try {
      final cameras =
          await availableCameras().timeout(
        const Duration(seconds: 8),
      );

      if (cameras.isEmpty) {
        throw Exception('Nenhuma câmera encontrada.');
      }

      CameraDescription camera = cameras.first;

      for (final item in cameras) {
        if (item.lensDirection == CameraLensDirection.back) {
          camera = item;
          break;
        }
      }

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      _controller = controller;

      await controller.initialize().timeout(
        const Duration(seconds: 10),
      );

      try {
        await controller.setFlashMode(FlashMode.auto);
      } catch (_) {}

      if (!mounted) return;

      setState(() {
        _inicializando = false;
        _erro = null;
      });
    } on TimeoutException {
      await _descartarController();

      if (!mounted) return;

      setState(() {
        _inicializando = false;
        _erro = 'A câmera demorou para responder.';
      });
    } catch (_) {
      await _descartarController();

      if (!mounted) return;

      setState(() {
        _inicializando = false;
        _erro = 'Não foi possível abrir a câmera.';
      });
    }
  }

  Future<void> _tirarFoto() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _capturando ||
        _emPreview) {
      return;
    }

    setState(() {
      _capturando = true;
    });

    try {
      final foto =
          await controller.takePicture().timeout(
        const Duration(seconds: 12),
      );

      if (!mounted) return;

      setState(() {
        _fotoTemporariaPath = foto.path;
        _capturando = false;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _capturando = false;
      });

      _mostrarErro(
        'A câmera demorou para salvar a foto. Tente novamente.',
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _capturando = false;
      });

      _mostrarErro(
        'Não foi possível tirar a foto.',
      );
    }
  }

  Future<void> _tirarNovamente() async {
    final path = _fotoTemporariaPath;
    final eraDaGaleria = _fotoDaGaleria;

    if (path == null) return;

    setState(() {
      _fotoTemporariaPath = null;
      _fotoDaGaleria = false;
    });

    // Uma imagem da galeria pertence ao motorista. Ela nunca deve ser
    // apagada ao trocar a seleção ou depois de salvar o canhoto.
    if (eraDaGaleria) return;

    try {
      final arquivo = File(path);

      if (await arquivo.exists()) {
        await arquivo.delete();
      }
    } catch (_) {}
  }

  Future<void> _escolherDaGaleria() async {
    if (_capturando) return;

    // Descarta somente a prévia atual. Se era foto da câmera, limpa o arquivo
    // temporário; se era da galeria, preserva a imagem original.
    if (_fotoTemporariaPath != null) {
      await _tirarNovamente();
    }

    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (foto == null || !mounted) return;

      final arquivo = File(foto.path);
      if (!await arquivo.exists()) {
        _mostrarErro('A imagem selecionada não está mais disponível.');
        return;
      }
      if (await arquivo.length() > 8 * 1024 * 1024) {
        _mostrarErro('Escolha uma imagem de até 8 MB.');
        return;
      }

      setState(() {
        _fotoTemporariaPath = foto.path;
        _fotoDaGaleria = true;
      });
    } catch (_) {
      _mostrarErro('Não foi possível abrir a galeria.');
    }
  }

  Future<void> _salvarFoto() async {
    final path = _fotoTemporariaPath;

    if (path == null || path.isEmpty) {
      return;
    }

    // Muito importante:
    // libera completamente a câmera ANTES de abrir
    // a câmera da próxima NF-e.
    //
    // Sem isso, alguns aparelhos deixam o preview
    // seguinte preto porque o novo CameraController
    // tenta abrir enquanto o anterior ainda segura
    // o hardware da câmera.
    await _descartarController();

    if (!mounted) {
      return;
    }

    Navigator.pop(
      context,
      CanhotoFotoResultado(
        caminho: path,
        removerArquivoOrigem: !_fotoDaGaleria,
      ),
    );
  }

  Future<bool> _confirmarSaida() async {
    if (!_emPreview) {
      return true;
    }

    final sair = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Descartar foto?'),
          content: const Text(
            'Esta foto ainda não foi salva.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CONTINUAR'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('DESCARTAR'),
            ),
          ],
        );
      },
    );

    if (sair == true) {
      await _tirarNovamente();
      return true;
    }

    return false;
  }

  Future<void> _descartarController() async {
    final controller = _controller;
    _controller = null;

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  void _mostrarErro(String texto) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texto),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final fotoPath = _fotoTemporariaPath;

    return PopScope(
      canPop: !_emPreview,
      onPopInvokedWithResult: (
        didPop,
        result,
      ) async {
        if (didPop) return;

        final podeSair = await _confirmarSaida();

        if (!mounted || !podeSair) return;

        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            'NF-e ${widget.numeroNfe}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Escolher da galeria',
              onPressed: _capturando ? null : _escolherDaGaleria,
              icon: const Icon(Icons.photo_library_outlined),
            ),
          ],
        ),
        body: SafeArea(
          child: _inicializando
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text(
                        'Abrindo câmera...',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : _erro != null
                  ? _buildErro()
                  : fotoPath != null
                      ? _buildPreview(fotoPath)
                      : controller == null ||
                              !controller.value.isInitialized
                          ? const Center(
                              child: Text(
                                'Câmera indisponível.',
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : _buildCamera(controller),
        ),
      ),
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white,
              size: 60,
            ),
            const SizedBox(height: 14),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _inicializando = true;
                  _erro = null;
                });

                _inicializar();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('TENTAR NOVAMENTE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera(
    CameraController controller,
  ) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: CameraPreview(controller),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Centralize o canhoto e tire a foto.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
                onPressed: _capturando ? null : _escolherDaGaleria,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('ESCOLHER DA GALERIA'),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 76,
                height: 76,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      _capturando ? null : _tirarFoto,
                  child: _capturando
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          size: 34,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(
    String fotoPath,
  ) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              10,
              6,
              10,
              8,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: Image.file(
                  File(fotoPath),
                  fit: BoxFit.contain,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return const Center(
                      child: Text(
                        'Não foi possível mostrar a foto.',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            14,
            10,
            14,
            16,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF101010),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    color: Colors.white70,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Confira se assinatura/carimbo estão legíveis.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(
                          color: Colors.white54,
                        ),
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: _tirarNovamente,
                      icon: const Icon(Icons.refresh),
                      label: Text(_fotoDaGaleria ? 'ESCOLHER OUTRA' : 'TIRAR NOVAMENTE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: _salvarFoto,
                      icon: const Icon(Icons.check),
                      label: const Text('SALVAR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
