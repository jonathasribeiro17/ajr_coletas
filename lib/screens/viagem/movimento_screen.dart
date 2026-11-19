import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/movimento.dart';
import '../../models/nota_fiscal.dart';
import '../../services/database_service.dart';
import '../coleta/scanner_screen.dart';

class MovimentoScreen extends StatefulWidget {
  final String viagemId;
  final TipoMovimento tipo;
  final String? cliente;

  // Mantemos a informação de PMZ apenas para identificação visual.
  // O fluxo de leitura é IGUAL ao de qualquer outra viagem.
  final bool modoPmz;

  // Quando preenchido, a tela abre em modo de edição.
  final Movimento? movimentoExistente;

  const MovimentoScreen({
    super.key,
    required this.viagemId,
    required this.tipo,
    this.cliente,
    this.modoPmz = false,
    this.movimentoExistente,
  });

  @override
  State<MovimentoScreen> createState() =>
      _MovimentoScreenState();
}

class _MovimentoScreenState
    extends State<MovimentoScreen> {
  final TextEditingController _notaController =
      TextEditingController();

  final List<NotaFiscal> _notas = [];

  bool _salvando = false;

  OverlayEntry? _feedbackEntry;
  Timer? _feedbackTimer;

  bool get _ehEdicao =>
      widget.movimentoExistente != null;

  bool get _ehAcrescimo =>
      widget.tipo ==
      TipoMovimento.acrescimo;

  String? get _clienteEfetivo =>
      widget.movimentoExistente?.cliente ??
      widget.cliente;

  String get _titulo {
    switch (widget.tipo) {
      case TipoMovimento.ida:
        return 'IDA';

      case TipoMovimento.retorno:
        return 'RETORNO';

      case TipoMovimento.acrescimo:
        return 'ACRÉSCIMO DE COLETA';
    }
  }

  IconData get _icone {
    switch (widget.tipo) {
      case TipoMovimento.ida:
        return Icons.local_shipping;

      case TipoMovimento.retorno:
        return Icons.keyboard_return;

      case TipoMovimento.acrescimo:
        return Icons.add_box;
    }
  }

  Color get _cor {
    switch (widget.tipo) {
      case TipoMovimento.ida:
        return Colors.blue;

      case TipoMovimento.retorno:
        return Colors.orange;

      case TipoMovimento.acrescimo:
        return Colors.indigo;
    }
  }

  @override
  void initState() {
    super.initState();

    final existente =
        widget.movimentoExistente;

    if (existente != null) {
      _notas.addAll(
        List<NotaFiscal>.from(
          existente.notas,
        ),
      );
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();

    final entry =
        _feedbackEntry;

    if (entry != null) {
      entry.remove();
      _feedbackEntry = null;
    }

    _notaController.dispose();
    super.dispose();
  }

  // ============================================================
  // SCANNER
  // ============================================================

  Future<void> _abrirScanner() async {
    if (_salvando) {
      return;
    }

    final codigos =
        await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                const ScannerScreen(),
      ),
    );

    if (codigos == null ||
        codigos.isEmpty) {
      return;
    }

    int adicionadas = 0;

    for (final codigo in codigos) {
      if (_adicionarCodigo(
        codigo,
        mostrarMensagem: false,
      )) {
        adicionadas++;
      }
    }

    if (!mounted) {
      return;
    }

    if (adicionadas > 0) {
      _feedbackRapido(
        adicionadas == 1
            ? 'NF-e adicionada'
            : '$adicionadas NF-es adicionadas',
      );
    }
  }

  // ============================================================
  // MANUAL
  // ============================================================

  void _adicionarNotaDigitada() {
    final codigo =
        _notaController.text
            .trim();

    if (codigo.isEmpty) {
      _mensagem(
        'Digite a chave da NF-e.',
      );
      return;
    }

    final adicionou =
        _adicionarCodigo(
      codigo,
    );

    if (adicionou) {
      _notaController.clear();

      _feedbackRapido(
        'NF-e adicionada',
      );
    }
  }

  // ============================================================
  // VALIDAR / ADICIONAR
  // ============================================================

  bool _adicionarCodigo(
    String original, {
    bool mostrarMensagem = true,
  }) {
    final codigo =
        NotaFiscal.limparChave(
      original,
    );

    if (codigo.length != 44) {
      if (mostrarMensagem) {
        _mensagem(
          'A chave deve possuir 44 números.',
          cor:
              Colors.red,
        );
      }

      return false;
    }

    if (!NotaFiscal.validarChaveNfe(
      codigo,
    )) {
      if (mostrarMensagem) {
        _mensagem(
          'Chave NF-e inválida.',
          cor:
              Colors.red,
        );
      }

      return false;
    }

    final duplicada =
        _notas.any(
      (nota) =>
          nota.chave ==
          codigo,
    );

    if (duplicada) {
      if (mostrarMensagem) {
        _mensagem(
          'Esta NF-e já foi adicionada.',
          cor:
              Colors.orange,
        );
      }

      return false;
    }

    setState(() {
      _notas.add(
        NotaFiscal(
          chave:
              codigo,
          dataLeitura:
              DateTime.now(),
        ),
      );
    });

    return true;
  }

  // ============================================================
  // REMOVER NF-e
  // ============================================================

  Future<void> _removerNota(
    int index,
  ) async {
    if (_salvando ||
        index < 0 ||
        index >= _notas.length) {
      return;
    }

    final nota =
        _notas[index];

    final confirmar =
        await showDialog<bool>(
      context:
          context,
      builder:
          (dialogContext) {
        return AlertDialog(
          icon:
              const Icon(
            Icons.delete_outline,
            color:
                Colors.red,
            size:
                44,
          ),
          title:
              const Text(
            'Excluir NF-e?',
          ),
          content:
              Text(
            'NF-e ${nota.numeroNfeFormatado}\n\n'
            'Ela será removida deste ${_ehEdicao ? 'movimento' : 'lançamento'}.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text(
                'CANCELAR',
              ),
            ),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    Colors.red,
                foregroundColor:
                    Colors.white,
              ),
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              icon:
                  const Icon(
                Icons.delete,
              ),
              label:
                  const Text(
                'EXCLUIR',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true ||
        !mounted) {
      return;
    }

    setState(() {
      _notas.removeAt(
        index,
      );
    });
  }

  // ============================================================
  // SALVAR
  // ============================================================

  Future<void> _salvarMovimento() async {
    if (_salvando) {
      return;
    }

    if (_notas.isEmpty) {
      _mensagem(
        'Adicione pelo menos uma NF-e.',
        cor:
            Colors.orange,
      );

      return;
    }

    if (_ehAcrescimo &&
        (_clienteEfetivo == null ||
            _clienteEfetivo!
                .trim()
                .isEmpty)) {
      _mensagem(
        'Informe o cliente / local do acréscimo.',
        cor:
            Colors.orange,
      );

      return;
    }

    final confirmar =
        await showDialog<bool>(
      context:
          context,
      builder:
          (dialogContext) {
        return AlertDialog(
          title:
              Text(
            _ehEdicao
                ? 'Salvar alterações?'
                : 'Finalizar $_titulo?',
          ),
          content:
              Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (widget.modoPmz) ...[
                const Row(
                  children: [
                    Icon(
                      Icons.flash_on,
                      color:
                          Colors.blue,
                      size:
                          20,
                    ),
                    SizedBox(
                      width:
                          7,
                    ),
                    Expanded(
                      child:
                          Text(
                        'PMZ: somente as chaves das NF-es serão enviadas. '
                        'O tratamento dos dados será feito no AJR Admin.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height:
                      14,
                ),
              ],

              if (_ehAcrescimo) ...[
                const Text(
                  'Cliente / Local',
                  style:
                      TextStyle(
                    fontSize:
                        11,
                    color:
                        Colors.grey,
                  ),
                ),
                const SizedBox(
                  height:
                      3,
                ),
                Text(
                  _clienteEfetivo ??
                      '-',
                  style:
                      const TextStyle(
                    fontSize:
                        17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height:
                      14,
                ),
              ],

              Text(
                '${_notas.length} NF-e(s).',
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text(
                'CANCELAR',
              ),
            ),
            FilledButton.icon(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              icon:
                  const Icon(
                Icons.save,
              ),
              label:
                  Text(
                _ehEdicao
                    ? 'SALVAR ALTERAÇÕES'
                    : 'SALVAR',
              ),
            ),
          ],
        );
      },
    );

    if (confirmar != true ||
        !mounted) {
      return;
    }

    setState(() {
      _salvando =
          true;
    });

    final existente =
        widget.movimentoExistente;

    final agora =
        DateTime.now();

    final movimento =
        Movimento(
      id:
          existente?.id ??
          agora
              .microsecondsSinceEpoch
              .toString(),
      viagemId:
          widget.viagemId,
      tipo:
          widget.tipo,
      cliente:
          _ehAcrescimo
              ? _clienteEfetivo
                  ?.trim()
              : null,
      dataHora:
          existente?.dataHora ??
          agora,
      notas:
          List<NotaFiscal>.from(
        _notas,
      ),
    );

    try {
      if (_ehEdicao) {
        await DatabaseService.instance
            .atualizarMovimento(
          movimento,
        );
      } else {
        await DatabaseService.instance
            .salvarMovimento(
          movimento,
        );
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mensagem(
        _ehEdicao
            ? 'Erro ao salvar alterações: $e'
            : 'Erro ao salvar: $e',
        cor:
            Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando =
              false;
        });
      }
    }
  }

  void _feedbackRapido(
    String texto,
  ) {
    if (!mounted) {
      return;
    }

    _feedbackTimer?.cancel();

    final anterior =
        _feedbackEntry;

    if (anterior != null) {
      anterior.remove();
      _feedbackEntry = null;
    }

    final overlay =
        Overlay.of(context);

    late final OverlayEntry entry;

    entry =
        OverlayEntry(
      builder:
          (overlayContext) {
        final topo =
            MediaQuery.paddingOf(
                  overlayContext,
                ).top +
                10;

        return Positioned(
          top: topo,
          left: 16,
          right: 16,
          child:
              IgnorePointer(
            child:
                Material(
              color:
                  Colors.transparent,
              child:
                  Center(
                child:
                    ConstrainedBox(
                  constraints:
                      const BoxConstraints(
                    maxWidth: 520,
                  ),
                  child:
                      Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 11,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFF1B5E20,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 14,
                          offset:
                              const Offset(
                            0,
                            4,
                          ),
                          color:
                              Colors.black.withValues(
                            alpha: 0.16,
                          ),
                        ),
                      ],
                    ),
                    child:
                        Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color:
                              Colors.white,
                          size: 21,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Flexible(
                          child:
                              Text(
                            texto,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _feedbackEntry =
        entry;

    overlay.insert(
      entry,
    );

    _feedbackTimer =
        Timer(
      const Duration(
        milliseconds: 850,
      ),
      () {
        if (_feedbackEntry ==
            entry) {
          entry.remove();
          _feedbackEntry = null;
        }
      },
    );
  }

  void _mensagem(
    String texto, {
    Color? cor,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(
          texto,
        ),
        backgroundColor:
            cor,
        behavior:
            SnackBarBehavior.floating,
        duration:
            const Duration(
          seconds: 2,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF5F7FA,
      ),
      appBar:
          AppBar(
        title:
            Text(
          _ehEdicao
              ? 'Editar $_titulo'
              : _titulo,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body:
          SafeArea(
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            16,
          ),
          child:
              Column(
            children: [
              // ==================================================
              // CABEÇALHO
              // ==================================================

              Container(
                width:
                    double.infinity,
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      theme
                          .colorScheme
                          .primaryContainer,
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                ),
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width:
                              46,
                          height:
                              46,
                          decoration:
                              BoxDecoration(
                            color:
                                _cor.withValues(
                              alpha:
                                  0.10,
                            ),
                            borderRadius:
                                BorderRadius.circular(
                              13,
                            ),
                          ),
                          child:
                              Icon(
                            _icone,
                            color:
                                _cor,
                          ),
                        ),
                        const SizedBox(
                          width:
                              12,
                        ),
                        Expanded(
                          child:
                              Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titulo,
                                style:
                                    const TextStyle(
                                  fontSize:
                                      18,
                                  fontWeight:
                                      FontWeight.bold,
                                ),
                              ),
                              Text(
                                _ehEdicao
                                    ? 'Edite as NF-es já registradas ou escaneie novas.'
                                    : 'Escaneie todas as NF-es deste movimento.',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.grey.shade700,
                                  fontSize:
                                      12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_ehEdicao)
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal:
                                  10,
                              vertical:
                                  5,
                            ),
                            decoration:
                                BoxDecoration(
                              color:
                                  Colors.green.withValues(
                                alpha:
                                    0.10,
                              ),
                              borderRadius:
                                  BorderRadius.circular(
                                20,
                              ),
                            ),
                            child:
                                const Text(
                              'EDITANDO',
                              style:
                                  TextStyle(
                                color:
                                    Colors.green,
                                fontSize:
                                    10,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),

                    if (widget.modoPmz) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal:
                              12,
                          vertical:
                              9,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.blue.withValues(
                            alpha:
                                0.08,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            10,
                          ),
                        ),
                        child:
                            const Row(
                          children: [
                            Icon(
                              Icons.flash_on,
                              size:
                                  18,
                              color:
                                  Colors.blue,
                            ),
                            SizedBox(
                              width:
                                  7,
                            ),
                            Expanded(
                              child:
                                  Text(
                                'PMZ RÁPIDO • escaneie normalmente. Sem fotos extras.',
                                style:
                                    TextStyle(
                                  color:
                                      Colors.blue,
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_ehAcrescimo &&
                        _clienteEfetivo != null) ...[
                      const SizedBox(
                        height:
                            12,
                      ),
                      Text(
                        'Cliente / Local: ${_clienteEfetivo!}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(
                height:
                    14,
              ),

              // ==================================================
              // SCANNER
              // ==================================================

              SizedBox(
                width:
                    double.infinity,
                height:
                    58,
                child:
                    FilledButton.icon(
                  onPressed:
                      _salvando
                          ? null
                          : _abrirScanner,
                  icon:
                      const Icon(
                    Icons.qr_code_scanner,
                  ),
                  label:
                      Text(
                    _ehEdicao
                        ? 'ESCANEAR MAIS NF-es'
                        : 'ESCANEAR NF-es',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height:
                    12,
              ),

              TextField(
                controller:
                    _notaController,
                enabled:
                    !_salvando,
                keyboardType:
                    TextInputType.number,
                maxLength:
                    44,
                onSubmitted:
                    (_) =>
                        _adicionarNotaDigitada(),
                decoration:
                    InputDecoration(
                  labelText:
                      'Chave manual',
                  hintText:
                      '44 dígitos',
                  counterText:
                      '',
                  prefixIcon:
                      const Icon(
                    Icons.keyboard,
                  ),
                  suffixIcon:
                      IconButton(
                    tooltip:
                        'Adicionar',
                    onPressed:
                        _salvando
                            ? null
                            : _adicionarNotaDigitada,
                    icon:
                        const Icon(
                      Icons.add_circle,
                    ),
                  ),
                  filled:
                      true,
                  fillColor:
                      Colors.white,
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height:
                    14,
              ),

              Row(
                children: [
                  const Expanded(
                    child:
                        Text(
                      'NF-es',
                      style:
                          TextStyle(
                        fontSize:
                            18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal:
                          12,
                      vertical:
                          6,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          _cor.withValues(
                        alpha:
                            0.10,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),
                    child:
                        Text(
                      '${_notas.length}',
                      style:
                          TextStyle(
                        color:
                            _cor,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height:
                    8,
              ),

              Expanded(
                child:
                    _notas.isEmpty
                        ? Center(
                            child:
                                Column(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size:
                                      54,
                                  color:
                                      Colors.grey.shade400,
                                ),
                                const SizedBox(
                                  height:
                                      12,
                                ),
                                Text(
                                  'Nenhuma NF-e adicionada.',
                                  style:
                                      TextStyle(
                                    color:
                                        Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount:
                                _notas.length,
                            separatorBuilder:
                                (_, _) =>
                                    const SizedBox(
                              height:
                                  7,
                            ),
                            itemBuilder:
                                (
                              context,
                              index,
                            ) {
                              final nota =
                                  _notas[index];

                              return Container(
                                decoration:
                                    BoxDecoration(
                                  color:
                                      Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(
                                    14,
                                  ),
                                  border:
                                      Border.all(
                                    color:
                                        const Color(
                                      0xFFE5E9F0,
                                    ),
                                  ),
                                ),
                                child:
                                    ListTile(
                                  dense:
                                      true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal:
                                        13,
                                    vertical:
                                        3,
                                  ),
                                  leading:
                                      CircleAvatar(
                                    backgroundColor:
                                        _cor.withValues(
                                      alpha:
                                          0.10,
                                    ),
                                    foregroundColor:
                                        _cor,
                                    child:
                                        Text(
                                      '${index + 1}',
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title:
                                      Text(
                                    'NF-e ${nota.numeroNfeFormatado}',
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                  subtitle:
                                      Text(
                                    nota.chave,
                                    maxLines:
                                        1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(
                                      fontSize:
                                          11,
                                    ),
                                  ),
                                  trailing:
                                      IconButton(
                                    tooltip:
                                        'Excluir NF-e',
                                    onPressed:
                                        _salvando
                                            ? null
                                            : () {
                                                _removerNota(
                                                  index,
                                                );
                                              },
                                    icon:
                                        const Icon(
                                      Icons.delete_outline,
                                      color:
                                          Colors.red,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),

              const SizedBox(
                height:
                    10,
              ),

              SizedBox(
                width:
                    double.infinity,
                height:
                    56,
                child:
                    FilledButton.icon(
                  onPressed:
                      _notas.isEmpty ||
                              _salvando
                          ? null
                          : _salvarMovimento,
                  icon:
                      _salvando
                          ? const SizedBox(
                              width:
                                  20,
                              height:
                                  20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : Icon(
                              _ehEdicao
                                  ? Icons.save
                                  : Icons.check_circle,
                            ),
                  label:
                      Text(
                    _salvando
                        ? 'SALVANDO...'
                        : _ehEdicao
                            ? 'SALVAR ALTERAÇÕES (${_notas.length})'
                            : 'FINALIZAR $_titulo (${_notas.length})',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
