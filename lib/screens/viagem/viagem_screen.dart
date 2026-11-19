import 'package:flutter/material.dart';

import '../../models/movimento.dart';
import '../../models/viagem.dart';
import '../../services/canhoto_sync_service.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';
import 'canhotos_viagem_screen.dart';
import 'movimento_screen.dart';

class ViagemScreen extends StatefulWidget {
  final Viagem viagem;

  const ViagemScreen({
    super.key,
    required this.viagem,
  });

  @override
  State<ViagemScreen> createState() =>
      _ViagemScreenState();
}

class _ViagemScreenState
    extends State<ViagemScreen> {
  late Viagem _viagem;
  bool _excluindoAcrescimo = false;

  @override
  void initState() {
    super.initState();

    _viagem =
        widget.viagem;

    _atualizarViagem();
  }

  // ============================================================
  // PMZ
  // ============================================================

  bool get _modoPmz {
    final destino =
        _viagem.destino
            .trim()
            .toUpperCase();

    final cliente =
        _viagem.cliente
            ?.trim()
            .toUpperCase();

    return destino.contains(
          'PMZ',
        ) ||
        (cliente?.contains(
              'PMZ',
            ) ??
            false);
  }

  // ============================================================
  // ATUALIZAR
  // ============================================================

  Future<void> _atualizarViagem() async {
    final viagem =
        await DatabaseService.instance
            .buscarViagemPorId(
      _viagem.id,
    );

    if (viagem != null && mounted) {
      setState(() {
        _viagem = viagem;
      });
    }
  }

  // ============================================================
  // ACRÉSCIMOS
  // ============================================================

  List<Movimento> get _acrescimos {
    return _viagem.movimentos
        .where(
          (movimento) =>
              movimento.tipo ==
              TipoMovimento.acrescimo,
        )
        .toList();
  }

  // ============================================================
  // MOVIMENTO EXISTENTE POR TIPO
  // ============================================================

  List<Movimento> _movimentosDoTipo(
    TipoMovimento tipo,
  ) {
    return _viagem.movimentos
        .where(
          (movimento) =>
              movimento.tipo ==
              tipo,
        )
        .toList();
  }

  Movimento? _movimentoPrincipal(
    TipoMovimento tipo,
  ) {
    final movimentos =
        _movimentosDoTipo(
      tipo,
    );

    if (movimentos.isEmpty) {
      return null;
    }

    // Se houver registros antigos duplicados,
    // abrimos o mais recente para edição.
    movimentos.sort(
      (a, b) =>
          a.dataHora.compareTo(
        b.dataHora,
      ),
    );

    return movimentos.last;
  }

  // ============================================================
  // TOTAL POR TIPO
  // ============================================================

  int _totalTipo(
    TipoMovimento tipo,
  ) {
    return _viagem.movimentos
        .where(
          (movimento) =>
              movimento.tipo ==
              tipo,
        )
        .fold(
          0,
          (
            total,
            movimento,
          ) =>
              total +
              movimento.notas.length,
        );
  }

  // ============================================================
  // CLIENTE DO ACRÉSCIMO
  // ============================================================

  Future<String?>
      _pedirClienteAcrescimo() async {
    final controller =
        TextEditingController();

    final cliente =
        await showDialog<String>(
      context: context,
      builder:
          (dialogContext) {
        return AlertDialog(
          title:
              const Text(
            'Novo acréscimo',
          ),
          content:
              SizedBox(
            width: 420,
            child:
                TextField(
              controller:
                  controller,
              autofocus:
                  true,
              textCapitalization:
                  TextCapitalization.words,
              decoration:
                  const InputDecoration(
                labelText:
                    'Cliente / Local',
                hintText:
                    'Ex.: Tenneco',
                prefixIcon:
                    Icon(
                  Icons.business,
                ),
                border:
                    OutlineInputBorder(),
              ),
              onSubmitted:
                  (_) {
                final valor =
                    controller.text.trim();

                if (valor.isNotEmpty) {
                  Navigator.pop(
                    dialogContext,
                    valor,
                  );
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text(
                'CANCELAR',
              ),
            ),
            FilledButton(
              onPressed:
                  () {
                final valor =
                    controller.text.trim();

                if (valor.isEmpty) {
                  return;
                }

                Navigator.pop(
                  dialogContext,
                  valor,
                );
              },
              child:
                  const Text(
                'CONTINUAR',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    return cliente;
  }

  // ============================================================
  // ABRIR MOVIMENTO
  // ============================================================

  Future<void> _abrirMovimento(
    TipoMovimento tipo, {
    Movimento? movimentoExistente,
  }) async {
    String? cliente;

    if (movimentoExistente != null) {
      cliente =
          movimentoExistente.cliente;
    } else if (tipo ==
        TipoMovimento.acrescimo) {
      cliente =
          await _pedirClienteAcrescimo();

      if (cliente == null ||
          cliente.isEmpty) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    final salvo =
        await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                MovimentoScreen(
          viagemId:
              _viagem.id,
          tipo:
              tipo,
          cliente:
              cliente,
          modoPmz:
              _modoPmz,
          movimentoExistente:
              movimentoExistente,
        ),
      ),
    );

    if (salvo == true) {
      // Primeiro atualiza do SQLite.
      await _atualizarViagem();

      // Depois sincroniza sem travar o motorista.
      SyncService.instance
          .sincronizarViagem(
        _viagem.id,
      );
    }
  }

  Future<void> _excluirAcrescimo(
    Movimento movimento,
  ) async {
    if (_excluindoAcrescimo) {
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(
            Icons.delete_forever,
            color: Colors.red,
            size: 50,
          ),
          title: const Text('Excluir acréscimo?'),
          content: Text(
            'Cliente / Local: ${movimento.cliente ?? 'Não informado'}\n\n'
            '${movimento.notas.length} NF-e(s)\n\n'
            'Este acréscimo e suas NF-es serão removidos da viagem.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCELAR'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete),
              label: const Text('EXCLUIR'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !mounted) {
      return;
    }

    setState(() {
      _excluindoAcrescimo = true;
    });

    try {
      await DatabaseService.instance.excluirMovimento(
        movimentoId: movimento.id,
        viagemId: _viagem.id,
      );

      await _atualizarViagem();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Acréscimo excluído.'),
          backgroundColor: Colors.green,
        ),
      );

      SyncService.instance.sincronizarViagem(_viagem.id);
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir acréscimo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _excluindoAcrescimo = false;
        });
      }
    }
  }

  // ============================================================
  // CANHOTOS
  // ============================================================

  Future<void> _abrirCanhotos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                CanhotosViagemScreen(
          viagem:
              _viagem,
        ),
      ),
    );

    await _atualizarViagem();
  }

  Future<bool> _confirmarCanhotosPendentes() async {
    final comCanhoto =
        await DatabaseService.instance
            .contarNotasComCanhoto(
      _viagem.id,
    );

    final faltando =
        _viagem.totalNotas -
            comCanhoto;

    if (faltando <= 0) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final acao =
        await showDialog<String>(
      context:
          context,
      builder:
          (dialogContext) {
        return AlertDialog(
          icon:
              const Icon(
            Icons.camera_alt_outlined,
            color:
                Colors.orange,
            size:
                48,
          ),
          title:
              Text(
            faltando == 1
                ? '1 NF-e sem canhoto'
                : '$faltando NF-es sem canhoto',
          ),
          content:
              Text(
            'Canhotos registrados: '
            '$comCanhoto de ${_viagem.totalNotas}.\n\n'
            'Você pode fotografar agora ou finalizar mesmo assim.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  'VOLTAR',
                );
              },
              child:
                  const Text(
                'VOLTAR',
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  'CANHOTOS',
                );
              },
              icon:
                  const Icon(
                Icons.camera_alt,
              ),
              label:
                  const Text(
                'VER CANHOTOS',
              ),
            ),
            FilledButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  'FINALIZAR',
                );
              },
              child:
                  const Text(
                'FINALIZAR MESMO ASSIM',
              ),
            ),
          ],
        );
      },
    );

    if (acao ==
        'CANHOTOS') {
      await _abrirCanhotos();

      return false;
    }

    return acao ==
        'FINALIZAR';
  }

  // ============================================================
  // FINALIZAR
  // ============================================================

  Future<void> _finalizarViagem() async {
    if (_viagem.totalNotas ==
        0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content:
              Text(
            'Adicione pelo menos uma NF-e antes de finalizar.',
          ),
        ),
      );

      return;
    }

    final podeFinalizar =
        await _confirmarCanhotosPendentes();

    if (!mounted) {
      return;
    }

    if (!podeFinalizar) {
      return;
    }

    final confirmar =
        await showDialog<bool>(
      context: context,
      builder:
          (context) {
        return AlertDialog(
          title:
              const Text(
            'Finalizar viagem?',
          ),
          content:
              Text(
            'Destino: ${_viagem.destino}\n\n'
            'IDA: ${_viagem.totalNotasIda} NF-e(s)\n'
            'Retorno: ${_viagem.totalNotasRetorno} NF-e(s)\n'
            'Acréscimos: ${_acrescimos.length}\n'
            'NF-es de acréscimo: ${_viagem.totalNotasAcrescimo}\n\n'
            'Total: ${_viagem.totalNotas} NF-e(s)',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child:
                  const Text(
                'CANCELAR',
              ),
            ),
            FilledButton(
              onPressed:
                  () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              child:
                  const Text(
                'FINALIZAR',
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

    try {
      await DatabaseService.instance
          .finalizarViagem(
        _viagem.id,
      );

      final viagemAtualizada =
          await DatabaseService.instance
              .buscarViagemPorId(
        _viagem.id,
      );

      if (viagemAtualizada == null) {
        throw Exception(
          'Não foi possível localizar a viagem finalizada.',
        );
      }

      final enviado =
          await SyncService.instance
              .sincronizarViagem(
        viagemAtualizada.id,
      );

      CanhotoSyncResumo canhotosResumo =
          const CanhotoSyncResumo(
        enviados: 0,
        erros: 0,
        pendentes: 0,
      );

      // O Worker precisa que viagem/movimentos/NF-es
      // já estejam no Supabase.
      //
      // Por isso os canhotos são enviados SOMENTE aqui,
      // depois da sincronização principal da viagem.
      if (enviado && mounted) {
        canhotosResumo =
            await _enviarCanhotosFinalizacao();
      }

      if (!mounted) {
        return;
      }

      await showDialog(
        context: context,
        builder:
            (context) {
          return AlertDialog(
            icon:
                Icon(
              enviado
                  ? Icons.cloud_done
                  : Icons.cloud_off,
              color:
                  enviado
                      ? Colors.green
                      : Colors.orange,
              size:
                  55,
            ),
            title:
                Text(
              enviado
                  ? 'Viagem finalizada e enviada!'
                  : 'Viagem finalizada',
            ),
            content:
                Text(
              enviado
                  ? '${viagemAtualizada.destino}\n\n'
                      '${viagemAtualizada.totalNotas} NF-e(s) registradas.\n'
                      '${_acrescimos.length} acréscimo(s).\n'
                      'Canhotos enviados: ${canhotosResumo.enviados}.'
                      '${canhotosResumo.pendentes > 0 ? '\nCanhotos pendentes: ${canhotosResumo.pendentes}.' : ''}\n\n'
                      'Dados enviados para o sistema.'
                  : '${viagemAtualizada.destino}\n\n'
                      '${viagemAtualizada.totalNotas} NF-e(s) registradas.\n\n'
                      'A viagem foi salva no celular, mas não foi possível enviar ao servidor agora. '
                      'Os canhotos permanecem salvos no aparelho.',
            ),
            actions: [
              FilledButton(
                onPressed:
                    () {
                  Navigator.pop(
                    context,
                  );
                },
                child:
                    const Text(
                  'OK',
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      Navigator.popUntil(
        context,
        (route) =>
            route.isFirst,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content:
              Text(
            'Erro ao finalizar viagem: $e',
          ),
          backgroundColor:
              Colors.red,
        ),
      );
    }
  }

  Future<CanhotoSyncResumo>
      _enviarCanhotosFinalizacao() async {
    final pendentesTodos =
        await DatabaseService.instance
            .buscarCanhotosPendentes();

    final pendentes =
        pendentesTodos
            .where(
              (item) =>
                  item.viagemId ==
                  _viagem.id,
            )
            .toList();

    if (pendentes.isEmpty) {
      return const CanhotoSyncResumo(
        enviados: 0,
        erros: 0,
        pendentes: 0,
      );
    }

    if (!mounted) {
      return CanhotoSyncResumo(
        enviados: 0,
        erros: 0,
        pendentes:
            pendentes.length,
      );
    }

    final resultado =
        await showDialog<CanhotoSyncResumo>(
      context:
          context,
      barrierDismissible:
          false,
      builder:
          (dialogContext) {
        return _EnvioCanhotosDialog(
          viagemId:
              _viagem.id,
          total:
              pendentes.length,
        );
      },
    );

    return resultado ??
        CanhotoSyncResumo(
          enviados: 0,
          erros: 0,
          pendentes:
              pendentes.length,
        );
  }

  // ============================================================
  // CANCELAR
  // ============================================================

  Future<void> _cancelarViagem() async {
    final confirmar =
        await showDialog<bool>(
      context: context,
      builder:
          (context) {
        return AlertDialog(
          icon:
              const Icon(
            Icons.warning_amber_rounded,
            color:
                Colors.red,
            size:
                50,
          ),
          title:
              const Text(
            'Cancelar viagem?',
          ),
          content:
              Text(
            'Destino: ${_viagem.destino}\n\n'
            'A viagem será marcada como CANCELADA.\n\n'
            'Deseja continuar?',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child:
                  const Text(
                'VOLTAR',
              ),
            ),
            FilledButton(
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
                  context,
                  true,
                );
              },
              child:
                  const Text(
                'SIM, CANCELAR',
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

    await DatabaseService.instance
        .cancelarViagem(
      _viagem.id,
    );

    // Tenta enviar o cancelamento ao Supabase sem bloquear a tela.
    SyncService.instance.sincronizarViagem(
      _viagem.id,
    );

    if (!mounted) {
      return;
    }

    Navigator.popUntil(
      context,
      (route) =>
          route.isFirst,
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
        Theme.of(
      context,
    );

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF5F7FA,
      ),
      appBar:
          AppBar(
        title:
            const Text(
          'Viagem em andamento',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      body:
          SafeArea(
        child:
            RefreshIndicator(
          onRefresh:
              _atualizarViagem,
          child:
              ListView(
            padding:
                const EdgeInsets.all(
              20,
            ),
            children: [
              // ================================================
              // CABEÇALHO
              // ================================================

              Container(
                padding:
                    const EdgeInsets.all(
                  18,
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
                    const Text(
                      'DESTINO',
                      style:
                          TextStyle(
                        fontSize:
                            11,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height:
                          5,
                    ),

                    Text(
                      _viagem.destino,
                      style:
                          const TextStyle(
                        fontSize:
                            23,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    if (_viagem.cliente !=
                        null) ...[
                      const SizedBox(
                        height:
                            5,
                      ),

                      Text(
                        _viagem.cliente!,
                        style:
                            const TextStyle(
                          fontSize:
                              16,
                        ),
                      ),
                    ],

                    const SizedBox(
                      height:
                          12,
                    ),

                    Text(
                      'Motorista: ${_viagem.motorista}',
                    ),

                    // ==========================================
                    // INDICADOR PMZ
                    // ==========================================

                    if (_modoPmz) ...[
                      const SizedBox(
                        height:
                            14,
                      ),

                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal:
                              12,
                          vertical:
                              8,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.blue.withValues(
                            alpha:
                                0.12,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            10,
                          ),
                        ),
                        child:
                            const Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.document_scanner,
                              size:
                                  18,
                              color:
                                  Colors.blue,
                            ),
                            SizedBox(
                              width:
                                  7,
                            ),
                            Text(
                              'MODO PMZ',
                              style:
                                  TextStyle(
                                color:
                                    Colors.blue,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(
                height:
                    25,
              ),

              _MovimentoCard(
                icon:
                    Icons.local_shipping,
                titulo:
                    'IDA',
                quantidade:
                    _totalTipo(
                  TipoMovimento.ida,
                ),
                color:
                    Colors.blue,
                onTap:
                    () {
                  _abrirMovimento(
                    TipoMovimento.ida,
                    movimentoExistente:
                        _movimentoPrincipal(
                      TipoMovimento.ida,
                    ),
                  );
                },
              ),

              const SizedBox(
                height:
                    12,
              ),

              _MovimentoCard(
                icon:
                    Icons.keyboard_return,
                titulo:
                    'RETORNO',
                quantidade:
                    _totalTipo(
                  TipoMovimento.retorno,
                ),
                color:
                    Colors.orange,
                onTap:
                    () {
                  _abrirMovimento(
                    TipoMovimento.retorno,
                    movimentoExistente:
                        _movimentoPrincipal(
                      TipoMovimento.retorno,
                    ),
                  );
                },
              ),

              const SizedBox(
                height:
                    28,
              ),

              Row(
                children: [
                  const Expanded(
                    child:
                        Text(
                      'ACRÉSCIMOS',
                      style:
                          TextStyle(
                        fontSize:
                            20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${_acrescimos.length}',
                    style:
                        const TextStyle(
                      fontSize:
                          18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height:
                    12,
              ),

              if (_acrescimos.isEmpty)
                Container(
                  padding:
                      const EdgeInsets.all(
                    22,
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
                      const Text(
                    'Nenhum acréscimo registrado.',
                    textAlign:
                        TextAlign.center,
                    style:
                        TextStyle(
                      color:
                          Colors.grey,
                    ),
                  ),
                ),

              for (int i = 0;
                  i <
                      _acrescimos.length;
                  i++)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom:
                        10,
                  ),
                  child:
                      _AcrescimoCard(
                    numero:
                        i + 1,
                    movimento:
                        _acrescimos[i],
                    bloqueado:
                        _excluindoAcrescimo,
                    onEditar: () {
                      _abrirMovimento(
                        TipoMovimento.acrescimo,
                        movimentoExistente:
                            _acrescimos[i],
                      );
                    },
                    onExcluir: () {
                      _excluirAcrescimo(
                        _acrescimos[i],
                      );
                    },
                  ),
                ),

              const SizedBox(
                height:
                    10,
              ),

              SizedBox(
                height:
                    55,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      () {
                    _abrirMovimento(
                      TipoMovimento.acrescimo,
                    );
                  },
                  icon:
                      const Icon(
                    Icons.add,
                  ),
                  label:
                      const Text(
                    'NOVO ACRÉSCIMO',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height:
                    25,
              ),

              Container(
                padding:
                    const EdgeInsets.all(
                  18,
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
                    Row(
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      size:
                          38,
                    ),

                    const SizedBox(
                      width:
                          14,
                    ),

                    const Expanded(
                      child:
                          Text(
                        'TOTAL DE NF-es',
                        style:
                            TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),

                    Text(
                      '${_viagem.totalNotas}',
                      style:
                          const TextStyle(
                        fontSize:
                            30,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height:
                    18,
              ),

              SizedBox(
                height:
                    58,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _viagem.totalNotas == 0
                          ? null
                          : _abrirCanhotos,
                  icon:
                      const Icon(
                    Icons.camera_alt,
                  ),
                  label:
                      const Text(
                    'CANHOTOS',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height:
                    14,
              ),

              SizedBox(
                height:
                    58,
                child:
                    FilledButton.icon(
                  onPressed:
                      _finalizarViagem,
                  icon:
                      const Icon(
                    Icons.flag,
                  ),
                  label:
                      const Text(
                    'FINALIZAR VIAGEM',
                    style:
                        TextStyle(
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

              SizedBox(
                height:
                    54,
                child:
                    OutlinedButton.icon(
                  onPressed:
                      _cancelarViagem,
                  icon:
                      const Icon(
                    Icons.cancel_outlined,
                    color:
                        Colors.red,
                  ),
                  label:
                      const Text(
                    'CANCELAR VIAGEM',
                    style:
                        TextStyle(
                      color:
                          Colors.red,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    side:
                        const BorderSide(
                      color:
                          Colors.red,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height:
                    20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CARD MOVIMENTO
// ============================================================

class _MovimentoCard
    extends StatelessWidget {
  final IconData icon;
  final String titulo;
  final int quantidade;
  final Color color;
  final VoidCallback onTap;

  const _MovimentoCard({
    required this.icon,
    required this.titulo,
    required this.quantidade,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Material(
      color:
          Colors.white,
      borderRadius:
          BorderRadius.circular(
        16,
      ),
      elevation:
          2,
      child:
          InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        child:
            Padding(
          padding:
              const EdgeInsets.all(
            18,
          ),
          child:
              Row(
            children: [
              Container(
                width:
                    55,
                height:
                    55,
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha:
                        0.1,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
                child:
                    Icon(
                  icon,
                  color:
                      color,
                  size:
                      30,
                ),
              ),

              const SizedBox(
                width:
                    15,
              ),

              Expanded(
                child:
                    Text(
                  titulo,
                  style:
                      const TextStyle(
                    fontSize:
                        16,
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
                      7,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha:
                        0.1,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child:
                    Text(
                  '$quantidade NF-e',
                  style:
                      TextStyle(
                    color:
                        color,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(
                width:
                    6,
              ),

              const Icon(
                Icons.chevron_right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CARD ACRÉSCIMO
// ============================================================

class _AcrescimoCard
    extends StatelessWidget {
  final int numero;
  final Movimento movimento;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final bool bloqueado;

  const _AcrescimoCard({
    required this.numero,
    required this.movimento,
    required this.onEditar,
    required this.onExcluir,
    this.bloqueado = false,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      child:
          ListTile(
        onTap:
            bloqueado
                ? null
                : onEditar,
        contentPadding:
            const EdgeInsets.all(
          14,
        ),
        leading:
            CircleAvatar(
          backgroundColor:
              Colors.indigo.withValues(
            alpha:
                0.12,
          ),
          child:
              Text(
            '$numero',
            style:
                const TextStyle(
              color:
                  Colors.indigo,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ),
        title:
            Text(
          movimento.cliente ??
              'Cliente não informado',
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Text(
          '${movimento.notas.length} NF-e(s) • toque para editar',
        ),
        trailing:
            IconButton(
          tooltip:
              'Excluir acréscimo',
          onPressed:
              bloqueado
                  ? null
                  : onExcluir,
          icon:
              const Icon(
            Icons.delete_outline,
            color:
                Colors.red,
          ),
        ),
      ),
    );
  }
}

class _EnvioCanhotosDialog
    extends StatefulWidget {
  final String viagemId;
  final int total;

  const _EnvioCanhotosDialog({
    required this.viagemId,
    required this.total,
  });

  @override
  State<_EnvioCanhotosDialog> createState() =>
      _EnvioCanhotosDialogState();
}

class _EnvioCanhotosDialogState
    extends State<_EnvioCanhotosDialog> {
  int _atual = 0;
  String _numeroNfe = '';
  String _etapa = 'Preparando';
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_iniciado) {
      return;
    }

    _iniciado = true;

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        _enviar();
      },
    );
  }

  Future<void> _enviar() async {
    final resultado =
        await CanhotoSyncService.instance
            .sincronizarNoFechamento(
      viagemId: widget.viagemId,
      onProgress: (
        atual,
        total,
        canhoto,
        etapa,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _atual = atual;
          _numeroNfe =
              canhoto.numeroNfe;
          _etapa = etapa;
        });
      },
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      resultado,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final total = widget.total;

    final atualVisual =
        _atual <= 0
            ? 1
            : _atual;

    final progresso =
        total <= 0
            ? 0.0
            : (atualVisual / total)
                .clamp(
              0.0,
              1.0,
            );

    // IMPORTANTE:
    // não usamos AlertDialog aqui.
    //
    // AlertDialog usa IntrinsicWidth internamente.
    // LinearProgressIndicator + IntrinsicWidth foi o que
    // gerou o "RenderBox was not laid out".
    //
    // Dialog + SizedBox dá uma largura real para a barra.
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding:
            const EdgeInsets.symmetric(
          horizontal: 28,
          vertical: 24,
        ),
        child: SizedBox(
          width: 330,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              22,
              24,
              22,
              22,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_upload_outlined,
                  size: 46,
                  color: Colors.blue,
                ),

                const SizedBox(
                  height: 12,
                ),

                const Text(
                  'Enviando canhotos',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                SizedBox(
                  width: double.infinity,
                  child:
                      LinearProgressIndicator(
                    value: progresso,
                    minHeight: 9,
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                Text(
                  '$atualVisual de $total',
                  style:
                      const TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                if (_numeroNfe
                    .isNotEmpty) ...[
                  const SizedBox(
                    height: 5,
                  ),

                  Text(
                    'NF-e $_numeroNfe',
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      color:
                          Colors.grey.shade700,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],

                const SizedBox(height: 6),

                Text(
                  _etapa,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                Text(
                  'Enviando as fotos antes de encerrar a viagem.',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    color:
                        Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

