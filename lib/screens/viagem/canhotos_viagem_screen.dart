import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/canhoto_local.dart';
import '../../models/movimento.dart';
import '../../models/nota_fiscal.dart';
import '../../models/viagem.dart';
import '../../services/canhoto_service.dart';
import 'canhoto_camera_screen.dart';

class CanhotosViagemScreen
    extends StatefulWidget {
  final Viagem viagem;

  const CanhotosViagemScreen({
    super.key,
    required this.viagem,
  });

  @override
  State<CanhotosViagemScreen> createState() =>
      _CanhotosViagemScreenState();
}

class _CanhotosViagemScreenState
    extends State<CanhotosViagemScreen> {
  final List<CanhotoLocal> _canhotos =
      [];

  bool _carregando = true;
  String? _fotografandoChave;

  @override
  void initState() {
    super.initState();

    _carregar();
  }

  Future<void> _carregar() async {
    final itens =
        await CanhotoService.instance
            .buscarViagem(
      widget.viagem.id,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _canhotos
        ..clear()
        ..addAll(
          itens,
        );

      _carregando = false;
    });
  }

  // ============================================================
  // NOTAS
  // ============================================================

  List<_NotaCanhotoItem> get _notas {
    final itens =
        <_NotaCanhotoItem>[];

    for (final movimento
        in widget.viagem.movimentos) {
      for (final nota
          in movimento.notas) {
        itens.add(
          _NotaCanhotoItem(
            movimento:
                movimento,
            nota:
                nota,
          ),
        );
      }
    }

    return itens;
  }

  List<CanhotoLocal> _fotosDaNota(
    _NotaCanhotoItem item,
  ) {
    return _canhotos.where(
      (canhoto) {
        return canhoto.movimentoId ==
                item.movimento.id &&
            canhoto.chaveNfe ==
                item.nota.chave;
      },
    ).toList();
  }

  List<_NotaCanhotoItem>
      get _pendentes {
    return _notas.where(
      (item) =>
          _fotosDaNota(
            item,
          ).isEmpty,
    ).toList();
  }

  int get _notasComCanhoto =>
      _notas.length -
      _pendentes.length;

  String? _clienteItem(
    _NotaCanhotoItem item,
  ) {
    final clienteMovimento =
        item.movimento.cliente
            ?.trim();

    if (clienteMovimento != null &&
        clienteMovimento.isNotEmpty) {
      return clienteMovimento;
    }

    final clienteViagem =
        widget.viagem.cliente
            ?.trim();

    if (clienteViagem != null &&
        clienteViagem.isNotEmpty) {
      return clienteViagem;
    }

    return null;
  }

  // ============================================================
  // CAPTURA DIRETA PELA LISTA
  // ============================================================

  Future<void> _iniciarDaNota(
    _NotaCanhotoItem inicial,
  ) async {
    if (_fotografandoChave != null) {
      return;
    }

    final pendentes =
        _pendentes;

    if (pendentes.isEmpty) {
      return;
    }

    final indice =
        pendentes.indexWhere(
      (item) =>
          item.movimento.id ==
              inicial.movimento.id &&
          item.nota.chave ==
              inicial.nota.chave,
    );

    final fila =
        <_NotaCanhotoItem>[];

    if (indice >= 0) {
      fila.addAll(
        pendentes.skip(
          indice,
        ),
      );

      fila.addAll(
        pendentes.take(
          indice,
        ),
      );
    } else {
      fila.addAll(
        pendentes,
      );
    }

    for (final item in fila) {
      if (!mounted) {
        return;
      }

      // Se, enquanto isso, a NF já ganhou foto,
      // simplesmente pula.
      if (_fotosDaNota(
        item,
      ).isNotEmpty) {
        continue;
      }

      final continuar =
          await _capturarUmaNota(
        item,
      );

      if (!continuar) {
        // O motorista apertou voltar/cancelou a câmera.
        // Fica exatamente na lista.
        break;
      }

      await _carregar();

      if (!mounted) {
        return;
      }

      // O for segue e a próxima câmera abre direto.
    }

    if (mounted) {
      setState(() {
        _fotografandoChave =
            null;
      });
    }
  }

  Future<bool> _capturarUmaNota(
    _NotaCanhotoItem item,
  ) async {
    setState(() {
      _fotografandoChave =
          item.nota.chave;
    });

    try {
      // A câmera é nossa própria tela.
      // Não usamos mais ImagePicker.
      final imagem =
          await Navigator.push<CanhotoFotoResultado>(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  CanhotoCameraScreen(
            numeroNfe:
                item.nota
                    .numeroNfeFormatado,
          ),
        ),
      );

      if (!mounted) {
        return false;
      }

      // Voltar da câmera = parar sequência
      // e permanecer na lista.
      if (imagem == null || imagem.caminho.isEmpty) {
        return false;
      }

      // Salva localmente com timeout.
      // Não há upload, resize nem compressão nesta etapa.
      await CanhotoService.instance
          .salvarFotoCapturada(
        imagemPath: imagem.caminho,
        removerArquivoOrigem: imagem.removerArquivoOrigem,
        viagem:
            widget.viagem,
        movimento:
            item.movimento,
        nota:
            item.nota,
      );

      if (!mounted) {
        return false;
      }

      await _carregar();

      // Dá tempo para o Android encerrar de vez a sessão
      // anterior da câmera antes de criar o próximo controller.
      //
      // É curto o bastante para o motorista não perceber,
      // mas evita o preview preto em vários aparelhos.
      await Future.delayed(
        const Duration(
          milliseconds: 350,
        ),
      );

      if (!mounted) {
        return false;
      }

      // Retorna true e o fluxo abre a próxima
      // NF pendente automaticamente.
      return true;
    } on TimeoutException {
      if (!mounted) {
        return false;
      }

      _mensagem(
        'A foto demorou para ser salva. Tente novamente.',
        cor:
            Colors.orange,
      );

      return false;
    } catch (e) {
      if (!mounted) {
        return false;
      }

      _mensagem(
        'Não foi possível salvar a foto: $e',
        cor:
            Colors.red,
      );

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _fotografandoChave =
              null;
        });
      }
    }
  }

  // ============================================================
  // VER FOTOS JÁ EXISTENTES
  // ============================================================

  Future<void> _verFotos(
    _NotaCanhotoItem item,
  ) async {
    final fotos =
        _fotosDaNota(
      item,
    );

    if (fotos.isEmpty) {
      await _iniciarDaNota(
        item,
      );

      return;
    }

    await showDialog<void>(
      context:
          context,
      builder:
          (dialogContext) {
        return Dialog(
          child:
              ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth:
                  620,
              maxHeight:
                  720,
            ),
            child:
                Padding(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child:
                  Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child:
                            Text(
                          'NF-e '
                          '${item.nota.numeroNfeFormatado}',
                          style:
                              const TextStyle(
                            fontSize:
                                20,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            () {
                          Navigator.pop(
                            dialogContext,
                          );
                        },
                        icon:
                            const Icon(
                          Icons.close,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height:
                        10,
                  ),

                  Expanded(
                    child:
                        ListView.separated(
                      itemCount:
                          fotos.length,
                      separatorBuilder:
                          (_, _) =>
                              const SizedBox(
                        height:
                            12,
                      ),
                      itemBuilder:
                          (
                        context,
                        index,
                      ) {
                        final foto =
                            fotos[index];

                        return Container(
                          padding:
                              const EdgeInsets.all(
                            8,
                          ),
                          decoration:
                              BoxDecoration(
                            border:
                                Border.all(
                              color:
                                  const Color(
                                0xFFE5E9F0,
                              ),
                            ),
                            borderRadius:
                                BorderRadius.circular(
                              12,
                            ),
                          ),
                          child:
                              Column(
                            children: [
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(
                                  9,
                                ),
                                child:
                                    Image.file(
                                  File(
                                    foto.localPath,
                                  ),
                                  height:
                                      330,
                                  width:
                                      double.infinity,
                                  fit:
                                      BoxFit.contain,
                                ),
                              ),

                              const SizedBox(
                                height:
                                    7,
                              ),

                              Row(
                                children: [
                                  Expanded(
                                    child:
                                        Text(
                                      'Foto ${index + 1}',
                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  const Icon(
                                    Icons.phone_android,
                                    color:
                                        Colors.green,
                                  ),

                                  IconButton(
                                    tooltip:
                                        'Excluir foto',
                                    onPressed:
                                        () async {
                                      final confirmar =
                                          await showDialog<bool>(
                                        context:
                                            context,
                                        builder:
                                            (context) {
                                          return AlertDialog(
                                            title:
                                                const Text(
                                              'Excluir foto?',
                                            ),
                                            content:
                                                const Text(
                                              'Esta foto será removida do celular.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(
                                                  context,
                                                  false,
                                                ),
                                                child:
                                                    const Text(
                                                  'CANCELAR',
                                                ),
                                              ),
                                              FilledButton(
                                                onPressed:
                                                    () =>
                                                        Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child:
                                                    const Text(
                                                  'EXCLUIR',
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );

                                      if (confirmar !=
                                          true) {
                                        return;
                                      }

                                      await CanhotoService.instance
                                          .excluir(
                                        foto,
                                      );

                                      if (!mounted ||
                                          !dialogContext.mounted) {
                                        return;
                                      }

                                      Navigator.pop(
                                        dialogContext,
                                      );

                                      await _carregar();
                                    },
                                    icon:
                                        const Icon(
                                      Icons.delete_outline,
                                      color:
                                          Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(
                    height:
                        12,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    height:
                        52,
                    child:
                        FilledButton.icon(
                      onPressed:
                          () {
                        Navigator.pop(
                          dialogContext,
                        );

                        _adicionarFotoExtra(
                          item,
                        );
                      },
                      icon:
                          const Icon(
                        Icons.add_a_photo,
                      ),
                      label:
                          const Text(
                        'ADICIONAR OUTRA FOTO',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _adicionarFotoExtra(
    _NotaCanhotoItem item,
  ) async {
    final salvou =
        await _capturarUmaNota(
      item,
    );

    if (!salvou ||
        !mounted) {
      return;
    }

    await _carregar();

  }

  void _mensagem(
    String texto, {
    Color? cor,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(
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
    final notas =
        _notas;

    final comCanhoto =
        _notasComCanhoto;

    final faltando =
        notas.length -
            comCanhoto;

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF5F7FA,
      ),
      appBar:
          AppBar(
        title:
            const Text(
          'Canhotos',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body:
          _carregando
              ? const Center(
                  child:
                      CircularProgressIndicator(),
                )
              : SafeArea(
                  child:
                      Column(
                    children: [
                      Container(
                        width:
                            double.infinity,
                        margin:
                            const EdgeInsets.fromLTRB(
                          16,
                          14,
                          16,
                          10,
                        ),
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.white,
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
                            Text(
                              widget
                                  .viagem
                                  .destino,
                              style:
                                  const TextStyle(
                                fontSize:
                                    20,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),

                            if (widget.viagem.cliente !=
                                null)
                              Text(
                                widget
                                    .viagem
                                    .cliente!,
                              ),

                            const SizedBox(
                              height:
                                  12,
                            ),

                            Row(
                              children: [
                                Expanded(
                                  child:
                                      _Resumo(
                                    titulo:
                                        'Com canhoto',
                                    valor:
                                        '$comCanhoto',
                                    icone:
                                        Icons.check_circle,
                                    cor:
                                        Colors.green,
                                  ),
                                ),

                                const SizedBox(
                                  width:
                                      10,
                                ),

                                Expanded(
                                  child:
                                      _Resumo(
                                    titulo:
                                        'Faltando',
                                    valor:
                                        '$faltando',
                                    icone:
                                        Icons.camera_alt_outlined,
                                    cor:
                                        faltando ==
                                                0
                                            ? Colors.green
                                            : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child:
                            notas.isEmpty
                                ? const Center(
                                    child:
                                        Text(
                                      'Nenhuma NF-e nesta viagem.',
                                    ),
                                  )
                                : ListView.separated(
                                    padding:
                                        const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      24,
                                    ),
                                    itemCount:
                                        notas.length,
                                    separatorBuilder:
                                        (_, _) =>
                                            const SizedBox(
                                      height:
                                          8,
                                    ),
                                    itemBuilder:
                                        (
                                      context,
                                      index,
                                    ) {
                                      final item =
                                          notas[index];

                                      final fotos =
                                          _fotosDaNota(
                                        item,
                                      );

                                      final tem =
                                          fotos.isNotEmpty;

                                      final cliente =
                                          _clienteItem(
                                        item,
                                      );

                                      final fotografando =
                                          _fotografandoChave ==
                                              item
                                                  .nota
                                                  .chave;

                                      return Material(
                                        color:
                                            Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(
                                          15,
                                        ),
                                        child:
                                            InkWell(
                                          borderRadius:
                                              BorderRadius.circular(
                                            15,
                                          ),
                                          onTap:
                                              fotografando
                                                  ? null
                                                  : () {
                                                      if (tem) {
                                                        _verFotos(
                                                          item,
                                                        );
                                                      } else {
                                                        _iniciarDaNota(
                                                          item,
                                                        );
                                                      }
                                                    },
                                          child:
                                              Padding(
                                            padding:
                                                const EdgeInsets.symmetric(
                                              horizontal:
                                                  14,
                                              vertical:
                                                  12,
                                            ),
                                            child:
                                                Row(
                                              children: [
                                                CircleAvatar(
                                                  backgroundColor:
                                                      tem
                                                          ? Colors.green.withValues(
                                                              alpha:
                                                                  0.12,
                                                            )
                                                          : Colors.orange.withValues(
                                                              alpha:
                                                                  0.12,
                                                            ),
                                                  foregroundColor:
                                                      tem
                                                          ? Colors.green
                                                          : Colors.orange,
                                                  child:
                                                      Icon(
                                                    tem
                                                        ? Icons.check
                                                        : fotografando
                                                            ? Icons.camera_alt
                                                            : Icons.camera_alt,
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
                                                        'NF-e '
                                                        '${item.nota.numeroNfeFormatado}',
                                                        style:
                                                            const TextStyle(
                                                          fontSize:
                                                              16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),

                                                      const SizedBox(
                                                        height:
                                                            3,
                                                      ),

                                                      Text(
                                                        [
                                                          item.movimento.tipoTexto,
                                                          ?cliente,
                                                        ].join(
                                                          ' • ',
                                                        ),
                                                        maxLines:
                                                            1,
                                                        overflow:
                                                            TextOverflow.ellipsis,
                                                        style:
                                                            TextStyle(
                                                          color:
                                                              Colors.grey.shade600,
                                                        ),
                                                      ),

                                                      const SizedBox(
                                                        height:
                                                            4,
                                                      ),

                                                      Text(
                                                        !tem
                                                            ? 'Toque e a câmera abre'
                                                            : '${fotos.length} foto(s) salva(s)',
                                                        style:
                                                            TextStyle(
                                                          color:
                                                              !tem
                                                                  ? Colors.orange
                                                                  : Colors.green,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                const SizedBox(
                                                  width:
                                                      8,
                                                ),

                                                Icon(
                                                  !tem
                                                      ? Icons.chevron_right
                                                      : Icons.photo_library_outlined,
                                                  color:
                                                      !tem
                                                          ? Colors.grey
                                                          : Colors.green,
                                                ),
                                              ],
                                            ),
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
  }
}

enum _AcaoFoto {
  salvar,
  tirarNovamente,
  cancelar,
}

class _NotaCanhotoItem {
  final Movimento movimento;
  final NotaFiscal nota;

  const _NotaCanhotoItem({
    required this.movimento,
    required this.nota,
  });
}

class _Resumo
    extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  const _Resumo({
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(
        12,
      ),
      decoration:
          BoxDecoration(
        color:
            cor.withValues(
          alpha:
              0.08,
        ),
        borderRadius:
            BorderRadius.circular(
          12,
        ),
      ),
      child:
          Row(
        children: [
          Icon(
            icone,
            color:
                cor,
          ),

          const SizedBox(
            width:
                8,
          ),

          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style:
                      TextStyle(
                    color:
                        cor,
                    fontSize:
                        20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                Text(
                  titulo,
                  style:
                      const TextStyle(
                    fontSize:
                        11,
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
