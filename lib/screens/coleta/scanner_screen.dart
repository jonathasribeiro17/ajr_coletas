import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/nota_fiscal.dart';

class ScannerScreen extends StatefulWidget {
  final int? limiteLeituras;
  final bool concluirAutomaticamente;

  const ScannerScreen({
    super.key,
    this.limiteLeituras,
    this.concluirAutomaticamente = false,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // ============================================================
  // SCANNER AO VIVO
  // ============================================================

  late final MobileScannerController _controller;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _imagePicker = ImagePicker();

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  // ============================================================
  // ESTADO
  // ============================================================

  final List<String> _codigos = <String>[];

  String? _ultimoCodigo;
  DateTime? _ultimaLeitura;

  bool _processandoBarcode = false;
  bool _processandoImagem = false;
  bool _saindo = false;
  bool _abrindoCameraFoto = false;

  bool _torchLigada = false;
  double _zoomAtual = 0.0;

  // Evita chamar start/stop da câmera simultaneamente.
  Future<void>? _operacaoCamera;

  @override
  void initState() {
    super.initState();

    _controller = MobileScannerController(
      autoStart: true,
      facing: CameraFacing.back,

      // DANFE / NF-e normalmente usa Code 128.
      formats: const [
        BarcodeFormat.code128,
      ],

      detectionSpeed: DetectionSpeed.normal,

      // Tempo curto sem exagerar no consumo.
      detectionTimeoutMs: 150,

      // Ajuda quando o código está pequeno na tela.
      autoZoom: true,

      // Zoom inicial leve.
      initialZoom: 0.05,
    );

    // Se o Android destruir a Activity durante seleção de imagem
    // pela galeria, recuperamos a imagem ao voltar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recuperarImagemPerdida();
    });
  }

  // ============================================================
  // CONTROLE SEGURO DA CÂMERA
  // ============================================================

  Future<void> _executarOperacaoCamera(
    Future<void> Function() operacao,
  ) async {
    final anterior = _operacaoCamera;

    if (anterior != null) {
      try {
        await anterior;
      } catch (_) {}
    }

    final futuro = operacao();
    _operacaoCamera = futuro;

    try {
      await futuro;
    } catch (_) {
      // Start/stop duplicado nunca deve derrubar a tela.
    } finally {
      if (identical(_operacaoCamera, futuro)) {
        _operacaoCamera = null;
      }
    }
  }

  Future<void> _pararScanner() async {
    await _executarOperacaoCamera(() async {
      await _controller.stop();
    });
  }

  Future<void> _iniciarScanner() async {
    if (_saindo ||
        _processandoImagem ||
        _abrindoCameraFoto ||
        !mounted) {
      return;
    }

    await _executarOperacaoCamera(() async {
      await _controller.start();
    });
  }

  // ============================================================
  // LEITURA AO VIVO
  // ============================================================

  Future<void> _codigoDetectado(
    BarcodeCapture capture,
  ) async {
    if (_processandoBarcode ||
        _processandoImagem ||
        _abrindoCameraFoto ||
        _saindo) {
      return;
    }

    _processandoBarcode = true;

    try {
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;

        if (raw == null || raw.trim().isEmpty) {
          continue;
        }

        final codigo = NotaFiscal.limparChave(raw);

        if (codigo.length != 44) {
          continue;
        }

        final agora = DateTime.now();

        // Evita dezenas de eventos do mesmo frame.
        if (_ultimoCodigo == codigo &&
            _ultimaLeitura != null &&
            agora.difference(_ultimaLeitura!).inMilliseconds < 900) {
          continue;
        }

        _ultimoCodigo = codigo;
        _ultimaLeitura = agora;

        if (!NotaFiscal.validarChaveNfe(codigo)) {
          await _feedbackErro(
            'Código lido, mas a chave NF-e é inválida.',
          );
          continue;
        }

        await _adicionarCodigo(codigo);
        break;
      }
    } finally {
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      _processandoBarcode = false;
    }
  }

  // ============================================================
  // ADICIONAR CHAVE
  // ============================================================

  Future<void> _adicionarCodigo(
    String codigo,
  ) async {
    if (_saindo) {
      return;
    }

    if (widget.limiteLeituras != null &&
        _codigos.length >= widget.limiteLeituras!) {
      return;
    }

    if (_codigos.contains(codigo)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta NF-e já foi adicionada.'),
            duration: Duration(milliseconds: 700),
          ),
        );
      }

      return;
    }

    if (!NotaFiscal.validarChaveNfe(codigo)) {
      await _feedbackErro(
        'A chave encontrada não passou na validação da NF-e.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _codigos.add(codigo);
    });

    await HapticFeedback.mediumImpact();

    try {
      await _audioPlayer.play(
        AssetSource('sounds/beep_ajr.wav'),
        volume: 1.0,
      );
    } catch (_) {
      // O som não pode impedir a operação.
    }

    if (!mounted) {
      return;
    }

    final nota = NotaFiscal(
      chave: codigo,
      dataLeitura: DateTime.now(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'NF-e ${nota.numeroNfeFormatado} adicionada.',
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 650),
        backgroundColor: Colors.green,
      ),
    );

    if (widget.concluirAutomaticamente &&
        widget.limiteLeituras != null &&
        _codigos.length >= widget.limiteLeituras!) {
      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      if (!mounted || _saindo) {
        return;
      }

      _saindo = true;

      Navigator.pop(
        context,
        List<String>.from(_codigos),
      );
    }
  }

  Future<void> _feedbackErro(
    String mensagem,
  ) async {
    await HapticFeedback.heavyImpact();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        duration: const Duration(milliseconds: 1000),
        backgroundColor: Colors.red,
      ),
    );
  }

  // ============================================================
  // FOTO INTERNA
  //
  // IMPORTANTE:
  // Não usamos ImagePicker.camera aqui.
  //
  // O ImagePicker abre a câmera externa do Android. Em aparelhos
  // com pouca memória o Android pode matar o processo do Flutter,
  // causando exatamente o efeito de "voltar para a tela inicial".
  //
  // Esta tela usa o plugin camera DENTRO do próprio Flutter.
  // ============================================================

  Future<void> _tirarFotoInterna() async {
    if (_abrindoCameraFoto ||
        _processandoImagem ||
        _saindo) {
      return;
    }

    setState(() {
      _abrindoCameraFoto = true;
    });

    await _pararScanner();

    String? caminho;

    try {
      if (!mounted) {
        return;
      }

      caminho = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => const _CapturaNfeScreen(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível abrir a câmera: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _abrindoCameraFoto = false;
        });
      }
    }

    if (caminho != null &&
        caminho.trim().isNotEmpty &&
        mounted) {
      await _processarImagem(caminho);
    }

    await _iniciarScanner();
  }

  // ============================================================
  // GALERIA
  // ============================================================

  Future<void> _abrirGaleria() async {
    if (_processandoImagem ||
        _abrindoCameraFoto ||
        _saindo) {
      return;
    }

    await _pararScanner();

    try {
      final imagem = await _imagePicker.pickImage(
        source: ImageSource.gallery,

        // Limita a imagem para não mandar uma foto gigante ao OCR.
        imageQuality: 88,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (imagem == null) {
        return;
      }

      await _processarImagem(imagem.path);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao abrir a imagem: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      await _iniciarScanner();
    }
  }

  // ============================================================
  // RECUPERAR IMAGEM PERDIDA DO IMAGE PICKER
  // ============================================================

  Future<void> _recuperarImagemPerdida() async {
    try {
      final resposta =
          await _imagePicker.retrieveLostData();

      if (resposta.isEmpty) {
        return;
      }

      final arquivos = resposta.files;

      if (arquivos == null || arquivos.isEmpty) {
        return;
      }

      final caminho = arquivos.first.path;

      if (!mounted || caminho.isEmpty) {
        return;
      }

      await _pararScanner();
      await _processarImagem(caminho);
      await _iniciarScanner();
    } catch (_) {
      // Não interrompe o scanner se não houver dados perdidos.
    }
  }

  // ============================================================
  // PROCESSAR FOTO
  //
  // Estratégia:
  // 1) Code 128 direto da imagem.
  // 2) OCR somente se o barcode não funcionar.
  //
  // Nunca executamos os dois simultaneamente.
  // ============================================================

  Future<void> _processarImagem(
    String caminho,
  ) async {
    if (_processandoImagem || _saindo) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _processandoImagem = true;
    });

    try {
      // ----------------------------------------------------------
      // TENTATIVA 1 - código de barras
      // ----------------------------------------------------------

      final chaveBarcode =
          await _lerBarcodeDaImagem(caminho);

      if (chaveBarcode != null) {
        await _adicionarCodigo(chaveBarcode);
        return;
      }

      // Dá uma pequena folga para câmera / ML Kit liberar recursos.
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      // ----------------------------------------------------------
      // TENTATIVA 2 - OCR
      // ----------------------------------------------------------

      final chaveOcr =
          await _lerChavePorOcr(caminho);

      if (chaveOcr != null) {
        await _adicionarCodigo(chaveOcr);
        return;
      }

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.document_scanner_outlined,
              color: Colors.orange,
              size: 52,
            ),
            title: const Text(
              'Não consegui identificar',
            ),
            content: const Text(
              'Não encontrei uma chave NF-e válida na foto.\n\n'
              'Tente novamente preenchendo a moldura somente com '
              'o código de barras e os números logo abaixo dele.\n\n'
              'Evite sombra, reflexo e foto muito inclinada.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('FECHAR'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);

                  // O processamento termina antes de abrir
                  // uma nova câmera.
                  Future<void>.delayed(
                    const Duration(milliseconds: 150),
                    _tirarFotoInterna,
                  );
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('TENTAR NOVAMENTE'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao analisar a NF-e: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processandoImagem = false;
        });
      }
    }
  }

  // ============================================================
  // BARCODE DA FOTO
  // ============================================================

  Future<String?> _lerBarcodeDaImagem(
    String caminho,
  ) async {
    try {
      final captura = await _controller.analyzeImage(
        caminho,
        formats: const [
          BarcodeFormat.code128,
        ],
      );

      if (captura == null) {
        return null;
      }

      for (final barcode in captura.barcodes) {
        final raw = barcode.rawValue;

        if (raw == null || raw.trim().isEmpty) {
          continue;
        }

        final codigo = NotaFiscal.limparChave(raw);

        if (codigo.length == 44 &&
            NotaFiscal.validarChaveNfe(codigo)) {
          return codigo;
        }
      }
    } catch (_) {
      // OCR será a segunda tentativa.
    }

    return null;
  }

  // ============================================================
  // OCR
  // ============================================================

  Future<String?> _lerChavePorOcr(
    String caminho,
  ) async {
    final inputImage = InputImage.fromFilePath(caminho);

    final resultado =
        await _textRecognizer.processImage(inputImage);

    final candidatas =
        _extrairCandidatasOcr(resultado.text);

    for (final candidata in candidatas) {
      if (NotaFiscal.validarChaveNfe(candidata)) {
        return candidata;
      }
    }

    return null;
  }

  // ============================================================
  // EXTRAÇÃO INTELIGENTE DO OCR
  // ============================================================

  List<String> _extrairCandidatasOcr(
    String texto,
  ) {
    final resultado = <String>{};

    // ----------------------------------------------------------
    // 1. Procura linha por linha.
    // ----------------------------------------------------------

    final linhas = texto.split(
      RegExp(r'[\r\n]+'),
    );

    for (final linhaOriginal in linhas) {
      if (linhaOriginal.trim().isEmpty) {
        continue;
      }

      final corrigida =
          _corrigirCaracteresOcr(linhaOriginal);

      final numeros =
          NotaFiscal.limparChave(corrigida);

      if (numeros.length == 44) {
        resultado.add(numeros);
      }
    }

    // ----------------------------------------------------------
    // 2. Procura 44 números com espaços/pontos/hífens.
    // ----------------------------------------------------------

    final textoCorrigido =
        _corrigirCaracteresOcr(texto);

    final regex44 = RegExp(
      r'(?<!\d)(?:\d[\s.\-]*){44}(?!\d)',
    );

    for (final match
        in regex44.allMatches(textoCorrigido)) {
      final trecho = match.group(0);

      if (trecho == null) {
        continue;
      }

      final chave = NotaFiscal.limparChave(trecho);

      if (chave.length == 44) {
        resultado.add(chave);
      }
    }

    // ----------------------------------------------------------
    // 3. Caso o OCR quebre os 44 dígitos em linhas próximas,
    //    testamos blocos consecutivos de texto.
    // ----------------------------------------------------------

    for (int inicio = 0;
        inicio < linhas.length;
        inicio++) {
      var acumulado = '';

      for (int fim = inicio;
          fim < linhas.length && fim < inicio + 4;
          fim++) {
        acumulado += ' ${linhas[fim]}';

        final corrigido =
            _corrigirCaracteresOcr(acumulado);

        final numeros =
            NotaFiscal.limparChave(corrigido);

        if (numeros.length == 44) {
          resultado.add(numeros);
        }

        if (numeros.length > 60) {
          break;
        }
      }
    }

    return resultado.toList();
  }

  // Correções conservadoras para OCR de sequência NUMÉRICA.
  String _corrigirCaracteresOcr(
    String valor,
  ) {
    return valor
        .toUpperCase()
        .replaceAll('O', '0')
        .replaceAll('Q', '0')
        .replaceAll('D', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('|', '1')
        .replaceAll('S', '5')
        .replaceAll('B', '8');
  }

  // ============================================================
  // DIGITAÇÃO MANUAL
  // ============================================================

  Future<void> _digitarChave() async {
    final textController =
        TextEditingController();

    final chave = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Digitar chave NF-e'),
          content: TextField(
            controller: textController,
            keyboardType: TextInputType.number,
            maxLength: 44,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Chave de acesso',
              hintText: '44 números',
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  NotaFiscal.limparChave(
                    textController.text,
                  ),
                );
              },
              child: const Text('VALIDAR'),
            ),
          ],
        );
      },
    );

    textController.dispose();

    if (chave == null || chave.isEmpty) {
      return;
    }

    await _adicionarCodigo(chave);
  }

  // ============================================================
  // OPÇÕES
  // ============================================================

  Future<void> _abrirOpcoes() async {
    if (_processandoImagem ||
        _abrindoCameraFoto ||
        _saindo) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              bottom: 15,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Não conseguiu ler?',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.camera_alt),
                  ),
                  title: const Text(
                    'Tirar foto do código',
                  ),
                  subtitle: const Text(
                    'Câmera interna — mais estável em celulares simples',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);

                    Future<void>.delayed(
                      const Duration(milliseconds: 100),
                      _tirarFotoInterna,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.photo_library),
                  ),
                  title: const Text(
                    'Escolher da galeria',
                  ),
                  subtitle: const Text(
                    'Analisa uma imagem já salva',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);

                    Future<void>.delayed(
                      const Duration(milliseconds: 100),
                      _abrirGaleria,
                    );
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.keyboard),
                  ),
                  title: const Text(
                    'Digitar chave',
                  ),
                  subtitle: const Text(
                    'Última opção caso a câmera não consiga',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);

                    Future<void>.delayed(
                      const Duration(milliseconds: 100),
                      _digitarChave,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // LANTERNA
  // ============================================================

  Future<void> _alternarLanterna() async {
    if (_processandoImagem ||
        _abrindoCameraFoto) {
      return;
    }

    try {
      await _controller.toggleTorch();

      if (!mounted) {
        return;
      }

      setState(() {
        _torchLigada = !_torchLigada;
      });
    } catch (_) {}
  }

  // ============================================================
  // ZOOM
  // ============================================================

  Future<void> _alterarZoom(
    double valor,
  ) async {
    final novo =
        valor.clamp(0.0, 1.0).toDouble();

    try {
      await _controller.setZoomScale(novo);

      if (!mounted) {
        return;
      }

      setState(() {
        _zoomAtual = novo;
      });
    } catch (_) {}
  }

  // ============================================================
  // LISTA DE LIDAS
  // ============================================================

  void _removerCodigo(
    int index,
  ) {
    if (index < 0 ||
        index >= _codigos.length) {
      return;
    }

    setState(() {
      _codigos.removeAt(index);
    });
  }

  Future<void> _mostrarLidas() async {
    if (_codigos.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setModalState,
          ) {
            return SafeArea(
              child: SizedBox(
                height:
                    MediaQuery.of(context).size.height *
                        0.65,
                child: Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'NF-es lidas',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          CircleAvatar(
                            child: Text(
                              '${_codigos.length}',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _codigos.length,
                        itemBuilder: (
                          context,
                          index,
                        ) {
                          final chave =
                              _codigos[index];

                          final nota =
                              NotaFiscal(
                            chave: chave,
                            dataLeitura:
                                DateTime.now(),
                          );

                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                '${index + 1}',
                              ),
                            ),
                            title: Text(
                              'NF-e ${nota.numeroNfeFormatado}',
                            ),
                            subtitle: Text(
                              chave,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'Remover',
                              onPressed: () {
                                _removerCodigo(index);

                                setModalState(() {});

                                if (_codigos.isEmpty) {
                                  Navigator.pop(
                                    sheetContext,
                                  );
                                }
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // CONCLUIR
  // ============================================================

  void _concluir() {
    if (_codigos.isEmpty || _saindo) {
      return;
    }

    _saindo = true;

    Navigator.pop(
      context,
      List<String>.from(_codigos),
    );
  }

  @override
  void dispose() {
    _saindo = true;

    _textRecognizer.close();
    _audioPlayer.dispose();
    _controller.dispose();

    super.dispose();
  }

  // ============================================================
  // TELA PRINCIPAL
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Escanear NF-es',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed:
                _processandoImagem ||
                        _abrindoCameraFoto
                    ? null
                    : _alternarLanterna,
            icon: Icon(
              _torchLigada
                  ? Icons.flashlight_off
                  : Icons.flashlight_on,
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final largura =
              constraints.maxWidth;

          final altura =
              constraints.maxHeight;

          final scanWidth =
              (largura - 28)
                  .clamp(280.0, 430.0)
                  .toDouble();

          final scanHeight =
              (scanWidth * 0.34)
                  .clamp(105.0, 150.0)
                  .toDouble();

          final scanWindow =
              Rect.fromCenter(
            center: Offset(
              largura / 2,
              altura * 0.40,
            ),
            width: scanWidth,
            height: scanHeight,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                scanWindow: scanWindow,
                fit: BoxFit.cover,
                tapToFocus: true,
                useAppLifecycleState: true,
                onDetect: _codigoDetectado,
                errorBuilder: (
                  context,
                  error,
                ) {
                  return Container(
                    color: Colors.black,
                    alignment:
                        Alignment.center,
                    padding:
                        const EdgeInsets.all(30),
                    child: const Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        Icon(
                          Icons
                              .camera_alt_outlined,
                          color: Colors.white,
                          size: 60,
                        ),
                        SizedBox(height: 15),
                        Text(
                          'Não foi possível abrir a câmera.',
                          textAlign:
                              TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              CustomPaint(
                painter: _ScannerOverlayPainter(
                  scanWindow: scanWindow,
                ),
              ),

              Positioned.fromRect(
                rect: scanWindow,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              Positioned(
                left: scanWindow.left + 12,
                right:
                    largura -
                        scanWindow.right +
                        12,
                top:
                    scanWindow.center.dy - 1,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent
                            .withValues(
                          alpha: 0.7,
                        ),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                top: 18,
                left: 18,
                right: 18,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap:
                        _codigos.isEmpty
                            ? null
                            : _mostrarLidas,
                    borderRadius:
                        BorderRadius.circular(14),
                    child: Container(
                      padding:
                          const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.black
                            .withValues(
                          alpha: 0.72,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          14,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'NF-es lidas',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration:
                                BoxDecoration(
                              color: Colors.green,
                              borderRadius:
                                  BorderRadius
                                      .circular(30),
                            ),
                            child: Text(
                              '${_codigos.length}',
                              style:
                                  const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: scanWindow.bottom + 15,
                left: 20,
                right: 20,
                child: const Text(
                  'Encaixe o código inteiro dentro da moldura.\n'
                  'Aproxime devagar e segure firme.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),

              Positioned(
                top: scanWindow.bottom + 70,
                left: 35,
                right: 35,
                child: Row(
                  children: [
                    const Icon(
                      Icons.zoom_out,
                      color: Colors.white,
                    ),
                    Expanded(
                      child: Slider(
                        value: _zoomAtual,
                        min: 0,
                        max: 1,
                        onChanged:
                            _processandoImagem ||
                                    _abrindoCameraFoto
                                ? null
                                : _alterarZoom,
                      ),
                    ),
                    const Icon(
                      Icons.zoom_in,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),

              if (_processandoImagem)
                Container(
                  color: Colors.black
                      .withValues(
                    alpha: 0.84,
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 18),
                        Text(
                          'Analisando NF-e...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'Código de barras → OCR',
                          style: TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              Positioned(
                bottom: 22,
                left: 18,
                right: 18,
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed:
                            _processandoImagem ||
                                    _abrindoCameraFoto
                                ? null
                                : _abrirOpcoes,
                        style:
                            OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.white,
                          side: const BorderSide(
                            color: Colors.white,
                          ),
                        ),
                        icon: const Icon(
                          Icons.document_scanner,
                        ),
                        label: const Text(
                          'NÃO CONSEGUIU LER?',
                          style: TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (!widget
                        .concluirAutomaticamente) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton.icon(
                          onPressed:
                              _codigos.isEmpty ||
                                      _processandoImagem ||
                                      _abrindoCameraFoto
                                  ? null
                                  : _concluir,
                          icon: const Icon(
                            Icons.check_circle,
                          ),
                          label: Text(
                            'CONCLUIR (${_codigos.length})',
                            style:
                                const TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// CÂMERA INTERNA PARA FOTO
// ============================================================

class _CapturaNfeScreen extends StatefulWidget {
  const _CapturaNfeScreen();

  @override
  State<_CapturaNfeScreen> createState() =>
      _CapturaNfeScreenState();
}

class _CapturaNfeScreenState
    extends State<_CapturaNfeScreen> {
  CameraController? _cameraController;

  bool _inicializando = true;
  bool _capturando = false;
  bool _flashLigado = false;

  String? _erro;

  @override
  void initState() {
    super.initState();

    _inicializarCamera();
  }

  Future<void> _inicializarCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'Nenhuma câmera disponível.',
        );
      }

      CameraDescription camera = cameras.first;

      for (final item in cameras) {
        if (item.lensDirection ==
            CameraLensDirection.back) {
          camera = item;
          break;
        }
      }

      final controller = CameraController(
        camera,

        // Boa resolução sem estourar memória no A03 Core.
        ResolutionPreset.high,

        enableAudio: false,
      );

      await controller.initialize();

      // Autofoco contínuo quando suportado.
      try {
        await controller.setFocusMode(
          FocusMode.auto,
        );
      } catch (_) {}

      // Flash começa desligado.
      try {
        await controller.setFlashMode(
          FlashMode.off,
        );
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _inicializando = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _erro = e.toString();
        _inicializando = false;
      });
    }
  }

  Future<void> _alternarFlash() async {
    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    final novo = !_flashLigado;

    try {
      await controller.setFlashMode(
        novo
            ? FlashMode.torch
            : FlashMode.off,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _flashLigado = novo;
      });
    } catch (_) {}
  }

  Future<void> _tirarFoto() async {
    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _capturando) {
      return;
    }

    setState(() {
      _capturando = true;
    });

    try {
      // Foca no centro pouco antes da foto.
      try {
        await controller.setFocusPoint(
          const Offset(0.5, 0.5),
        );

        await Future.delayed(
          const Duration(milliseconds: 200),
        );
      } catch (_) {}

      final arquivo =
          await controller.takePicture();

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        arquivo.path,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao tirar foto: $e',
          ),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        _capturando = false;
      });
    }
  }

  @override
  void dispose() {
    final controller =
        _cameraController;

    _cameraController = null;

    if (controller != null) {
      unawaited(controller.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_inicializando) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_erro != null ||
        _cameraController == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text(
            'Foto da NF-e',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Não foi possível abrir a câmera.\n\n'
              '${_erro ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    final controller =
        _cameraController!;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Fotografar código da NF-e',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            onPressed:
                _capturando
                    ? null
                    : _alternarFlash,
            icon: Icon(
              _flashLigado
                  ? Icons.flashlight_off
                  : Icons.flashlight_on,
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(
            controller,
          ),

          Container(
            color: Colors.black.withValues(
              alpha: 0.08,
            ),
          ),

          Center(
            child: Container(
              margin:
                  const EdgeInsets.symmetric(
                horizontal: 18,
              ),
              height: 210,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
                borderRadius:
                    BorderRadius.circular(16),
              ),
              child: const Center(
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Text(
                    'Código de barras + números',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      backgroundColor:
                          Colors.black54,
                      fontSize: 16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 18,
            left: 18,
            right: 18,
            child: Container(
              padding:
                  const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.black
                    .withValues(
                  alpha: 0.72,
                ),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: const Text(
                'Fotografe somente a região do código.\n'
                'Não precisa pegar a folha inteira.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withValues(
                      alpha: 0.72,
                    ),
                    borderRadius:
                        BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Deixe o código reto, próximo e sem reflexo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: FilledButton.icon(
                    onPressed:
                        _capturando
                            ? null
                            : _tirarFoto,
                    icon:
                        _capturando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt,
                              ),
                    label: Text(
                      _capturando
                          ? 'CAPTURANDO...'
                          : 'TIRAR FOTO',
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// OVERLAY DO SCANNER
// ============================================================

class _ScannerOverlayPainter
    extends CustomPainter {
  final Rect scanWindow;

  const _ScannerOverlayPainter({
    required this.scanWindow,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = Colors.black.withValues(
        alpha: 0.48,
      );

    final path = Path()
      ..addRect(
        Offset.zero & size,
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          scanWindow,
          const Radius.circular(14),
        ),
      )
      ..fillType =
          PathFillType.evenOdd;

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _ScannerOverlayPainter
        oldDelegate,
  ) {
    return oldDelegate.scanWindow !=
        scanWindow;
  }
}
