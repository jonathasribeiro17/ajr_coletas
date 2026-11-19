import 'package:flutter/material.dart';

import '../../models/canhoto_local.dart';
import '../../models/viagem.dart';
import '../../services/canhoto_sync_service.dart';
import '../../services/database_service.dart';
import '../../services/sync_service.dart';

class HistoricoViagensScreen
    extends StatefulWidget {
  final String nomeMotorista;

  const HistoricoViagensScreen({
    super.key,
    required this.nomeMotorista,
  });

  @override
  State<HistoricoViagensScreen> createState() =>
      _HistoricoViagensScreenState();
}

class _HistoricoViagensScreenState
    extends State<HistoricoViagensScreen> {
  late Future<List<Viagem>> _viagensFuture;

  final Map<String, List<CanhotoLocal>>
      _canhotosPorViagem = {};

  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    _sincronizarSilencioso();
  }

  void _carregar() {
    _viagensFuture =
        DatabaseService.instance
            .buscarViagensMotorista(
      widget.nomeMotorista,
    );
  }

  Future<List<CanhotoLocal>>
      _canhotosDaViagem(
    String viagemId,
  ) async {
    final cache =
        _canhotosPorViagem[
            viagemId];

    if (cache != null) {
      return cache;
    }

    final itens =
        await DatabaseService.instance
            .buscarCanhotosViagem(
      viagemId,
    );

    _canhotosPorViagem[
        viagemId] = itens;

    return itens;
  }

  Future<void>
      _sincronizarSilencioso() async {
    if (_sincronizando) {
      return;
    }

    _sincronizando = true;

    try {
      // Primeiro envia viagem/movimentos/NF-es.
      await SyncService.instance
          .sincronizarPendentes();

      // Só depois tenta as fotos de viagens finalizadas.
      await CanhotoSyncService.instance
          .sincronizarPendentesFinalizados();

      _canhotosPorViagem.clear();

      if (!mounted) {
        return;
      }

      setState(() {
        _carregar();
      });
    } catch (_) {
      // Sem internet: continua mostrando o estado local.
    } finally {
      _sincronizando = false;
    }
  }

  Future<void> _atualizar() async {
    await _sincronizarSilencioso();

    _canhotosPorViagem.clear();

    if (!mounted) {
      return;
    }

    setState(() {
      _carregar();
    });

    await _viagensFuture;
  }

  String _formatarData(
    DateTime data,
  ) {
    final dia =
        data.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final mes =
        data.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    final ano =
        data.year
            .toString();

    final hora =
        data.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minuto =
        data.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$dia/$mes/$ano às $hora:$minuto';
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF5F7FA,
      ),
      appBar: AppBar(
        title:
            const Text(
          'Minhas Viagens',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        actions: [
          if (_sincronizando)
            const Padding(
              padding:
                  EdgeInsets.only(
                right: 16,
              ),
              child:
                  Center(
                child:
                    SizedBox(
                  width: 19,
                  height: 19,
                  child:
                      CircularProgressIndicator(
                    strokeWidth:
                        2,
                  ),
                ),
              ),
            ),
        ],
      ),
      body:
          FutureBuilder<
              List<Viagem>>(
        future:
            _viagensFuture,
        builder:
            (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState ==
              ConnectionState
                  .waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child:
                  Text(
                'Erro ao carregar viagens:\n'
                '${snapshot.error}',
                textAlign:
                    TextAlign.center,
              ),
            );
          }

          final viagens =
              snapshot.data ??
                  [];

          if (viagens.isEmpty) {
            return RefreshIndicator(
              onRefresh:
                  _atualizar,
              child:
                  ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(
                    height: 150,
                  ),
                  Icon(
                    Icons.route_outlined,
                    size: 80,
                    color:
                        Colors.grey.shade400,
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  const Center(
                    child:
                        Text(
                      'Nenhuma viagem encontrada',
                      style:
                          TextStyle(
                        fontSize:
                            18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh:
                _atualizar,
            child:
                ListView.separated(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              itemCount:
                  viagens.length,
              separatorBuilder:
                  (
                context,
                index,
              ) {
                return const SizedBox(
                  height: 10,
                );
              },
              itemBuilder:
                  (
                context,
                index,
              ) {
                final viagem =
                    viagens[index];

                return FutureBuilder<
                    List<
                        CanhotoLocal>>(
                  future:
                      _canhotosDaViagem(
                    viagem.id,
                  ),
                  builder:
                      (
                    context,
                    canhotosSnapshot,
                  ) {
                    final canhotos =
                        canhotosSnapshot
                                .data ??
                            const <
                                CanhotoLocal>[];

                    final status =
                        _StatusCanhotos.from(
                      viagem:
                          viagem,
                      canhotos:
                          canhotos,
                    );

                    return Card(
                      child:
                          ExpansionTile(
                        leading:
                            CircleAvatar(
                          backgroundColor:
                              _corFundoStatus(
                            viagem,
                            status,
                          ),
                          child:
                              Icon(
                            _iconeStatus(
                              viagem,
                              status,
                            ),
                            color:
                                _corStatus(
                              viagem,
                              status,
                            ),
                          ),
                        ),
                        title:
                            Text(
                          viagem.destino,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        subtitle:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatarData(
                                viagem.dataInicio,
                              ),
                            ),

                            if (viagem.status ==
                                'FINALIZADA')
                              Padding(
                                padding:
                                    const EdgeInsets.only(
                                  top: 4,
                                ),
                                child:
                                    _StatusCanhotoCompacto(
                                  status:
                                      status,
                                ),
                              ),
                          ],
                        ),
                        children: [
                          const Divider(
                            height: 1,
                          ),

                          Padding(
                            padding:
                                const EdgeInsets.all(
                              16,
                            ),
                            child:
                                Column(
                              children: [
                                if (viagem.cliente !=
                                    null)
                                  _LinhaInfo(
                                    titulo:
                                        'Cliente / Local',
                                    valor:
                                        viagem.cliente!,
                                  ),

                                if (viagem.status ==
                                    'FINALIZADA')
                                  _LinhaInfo(
                                    titulo:
                                        'Viagem',
                                    valor:
                                        viagem.sincronizada
                                            ? 'ENVIADA'
                                            : 'PENDENTE',
                                    corValor:
                                        viagem.sincronizada
                                            ? Colors.green
                                            : Colors.orange,
                                  ),

                                if (viagem.status ==
                                    'FINALIZADA') ...[
                                  _LinhaInfo(
                                    titulo:
                                        'NF-es com canhoto',
                                    valor:
                                        '${status.notasComFoto}/${status.totalNotas}',
                                    corValor:
                                        status.notasComFoto ==
                                                status.totalNotas &&
                                            status.totalNotas >
                                                0
                                            ? Colors.green
                                            : Colors.orange,
                                  ),

                                  _LinhaInfo(
                                    titulo:
                                        'Fotos no R2',
                                    valor:
                                        '${status.fotosEnviadas}/${status.totalFotos}',
                                    corValor:
                                        status.totalFotos >
                                                    0 &&
                                                status.fotosEnviadas ==
                                                    status.totalFotos
                                            ? Colors.green
                                            : status.totalFotos ==
                                                    0
                                                ? Colors.grey
                                                : Colors.orange,
                                  ),

                                  if (status.fotosPendentes >
                                      0)
                                    _LinhaInfo(
                                      titulo:
                                          'Fotos pendentes',
                                      valor:
                                          '${status.fotosPendentes}',
                                      corValor:
                                          Colors.orange,
                                    ),
                                ],

                                _LinhaInfo(
                                  titulo:
                                      'Status',
                                  valor:
                                      viagem.status,
                                ),

                                _LinhaInfo(
                                  titulo:
                                      'IDA',
                                  valor:
                                      '${viagem.totalNotasIda} NF-e(s)',
                                ),

                                _LinhaInfo(
                                  titulo:
                                      'Retorno',
                                  valor:
                                      '${viagem.totalNotasRetorno} NF-e(s)',
                                ),

                                _LinhaInfo(
                                  titulo:
                                      'Acréscimo',
                                  valor:
                                      '${viagem.totalNotasAcrescimo} NF-e(s)',
                                ),

                                const Divider(),

                                _LinhaInfo(
                                  titulo:
                                      'TOTAL',
                                  valor:
                                      '${viagem.totalNotas} NF-e(s)',
                                  destaque:
                                      true,
                                ),

                                const SizedBox(
                                  height: 12,
                                ),

                                SizedBox(
                                  width:
                                      double.infinity,
                                  child:
                                      OutlinedButton.icon(
                                    onPressed:
                                        () {
                                      _mostrarNotas(
                                        context,
                                        viagem,
                                        canhotos,
                                      );
                                    },
                                    icon:
                                        const Icon(
                                      Icons.receipt_long,
                                    ),
                                    label:
                                        const Text(
                                      'VER NF-es E CANHOTOS',
                                    ),
                                  ),
                                ),

                                if (status.fotosPendentes >
                                    0) ...[
                                  const SizedBox(
                                    height: 8,
                                  ),

                                  SizedBox(
                                    width:
                                        double.infinity,
                                    child:
                                        FilledButton.icon(
                                      onPressed:
                                          _sincronizando
                                              ? null
                                              : () async {
                                                  await _sincronizarSilencioso();

                                                  if (!mounted) {
                                                    return;
                                                  }

                                                  _canhotosPorViagem
                                                      .remove(
                                                    viagem.id,
                                                  );

                                                  setState(() {});
                                                },
                                      icon:
                                          const Icon(
                                        Icons.cloud_upload_outlined,
                                      ),
                                      label:
                                          const Text(
                                        'TENTAR ENVIAR CANHOTOS',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  Color _corStatus(
    Viagem viagem,
    _StatusCanhotos status,
  ) {
    if (viagem.status ==
        'ABERTA') {
      return Colors.blue;
    }

    if (viagem.status ==
        'CANCELADA') {
      return Colors.red;
    }

    if (status.totalFotos >
            0 &&
        status.fotosPendentes ==
            0 &&
        viagem.sincronizada) {
      return Colors.green;
    }

    return Colors.orange;
  }

  Color _corFundoStatus(
    Viagem viagem,
    _StatusCanhotos status,
  ) {
    return _corStatus(
      viagem,
      status,
    ).withValues(
      alpha: 0.15,
    );
  }

  IconData _iconeStatus(
    Viagem viagem,
    _StatusCanhotos status,
  ) {
    if (viagem.status ==
        'ABERTA') {
      return Icons.local_shipping;
    }

    if (viagem.status ==
        'CANCELADA') {
      return Icons.close;
    }

    if (status.fotosPendentes >
        0) {
      return Icons.cloud_upload_outlined;
    }

    if (status.totalFotos >
        0) {
      return Icons.cloud_done;
    }

    return viagem.sincronizada
        ? Icons.check_circle_outline
        : Icons.cloud_upload_outlined;
  }

  void _mostrarNotas(
    BuildContext context,
    Viagem viagem,
    List<CanhotoLocal> canhotos,
  ) {
    showModalBottomSheet(
      context:
          context,
      isScrollControlled:
          true,
      builder:
          (context) {
        return DraggableScrollableSheet(
          expand:
              false,
          initialChildSize:
              0.78,
          maxChildSize:
              0.95,
          builder:
              (
            context,
            scrollController,
          ) {
            return ListView(
              controller:
                  scrollController,
              padding:
                  const EdgeInsets.all(
                20,
              ),
              children: [
                Text(
                  viagem.destino,
                  style:
                      const TextStyle(
                    fontSize:
                        23,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                const Text(
                  'Status local dos canhotos',
                  style:
                      TextStyle(
                    color:
                        Colors.grey,
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),

                for (final movimento
                    in viagem.movimentos) ...[
                  Text(
                    movimento.tipoTexto,
                    style:
                        const TextStyle(
                      fontSize:
                          18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  for (var i = 0;
                      i <
                          movimento
                              .notas
                              .length;
                      i++)
                    Builder(
                      builder:
                          (context) {
                        final nota =
                            movimento.notas[i];

                        final fotos =
                            canhotos.where(
                          (foto) =>
                              foto.movimentoId ==
                                  movimento.id &&
                              foto.chaveNfe ==
                                  nota.chave,
                        ).toList();

                        final enviadas =
                            fotos
                                .where(
                                  (foto) =>
                                      foto.enviado,
                                )
                                .length;

                        final pendentes =
                            fotos.length -
                                enviadas;

                        return Card(
                          child:
                              ListTile(
                            leading:
                                CircleAvatar(
                              backgroundColor:
                                  fotos.isEmpty
                                      ? Colors.grey.withValues(
                                          alpha:
                                              0.15,
                                        )
                                      : pendentes ==
                                              0
                                          ? Colors.green.withValues(
                                              alpha:
                                                  0.15,
                                            )
                                          : Colors.orange.withValues(
                                              alpha:
                                                  0.15,
                                            ),
                              child:
                                  Icon(
                                fotos.isEmpty
                                    ? Icons.no_photography_outlined
                                    : pendentes ==
                                            0
                                        ? Icons.cloud_done
                                        : Icons.cloud_upload_outlined,
                                color:
                                    fotos.isEmpty
                                        ? Colors.grey
                                        : pendentes ==
                                                0
                                            ? Colors.green
                                            : Colors.orange,
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
                                Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  nota.chave,
                                  style:
                                      const TextStyle(
                                    fontSize:
                                        10,
                                  ),
                                ),

                                const SizedBox(
                                  height: 5,
                                ),

                                if (fotos.isEmpty)
                                  const Text(
                                    'Sem canhoto salvo',
                                    style:
                                        TextStyle(
                                      color:
                                          Colors.grey,
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  )
                                else
                                  Text(
                                    pendentes ==
                                            0
                                        ? '${fotos.length} foto(s) • ENVIADA(S)'
                                        : '$enviadas enviada(s) • $pendentes pendente(s)',
                                    style:
                                        TextStyle(
                                      color:
                                          pendentes ==
                                                  0
                                              ? Colors.green
                                              : Colors.orange,
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),

                                for (final foto
                                    in fotos)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(
                                      top: 3,
                                    ),
                                    child:
                                        Row(
                                      children: [
                                        Icon(
                                          foto.enviado
                                              ? Icons.check_circle
                                              : Icons.schedule,
                                          size:
                                              14,
                                          color:
                                              foto.enviado
                                                  ? Colors.green
                                                  : Colors.orange,
                                        ),

                                        const SizedBox(
                                          width: 5,
                                        ),

                                        Expanded(
                                          child:
                                              Text(
                                            foto.enviado
                                                ? 'R2: ${foto.storagePath ?? 'enviado'}'
                                                : 'Aguardando envio',
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(
                                              fontSize:
                                                  11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                  const SizedBox(
                    height: 18,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}


class _StatusCanhotos {
  final int totalNotas;
  final int notasComFoto;
  final int totalFotos;
  final int fotosEnviadas;

  const _StatusCanhotos({
    required this.totalNotas,
    required this.notasComFoto,
    required this.totalFotos,
    required this.fotosEnviadas,
  });

  int get fotosPendentes =>
      totalFotos -
      fotosEnviadas;

  factory _StatusCanhotos.from({
    required Viagem viagem,
    required List<CanhotoLocal> canhotos,
  }) {
    final notasComFoto =
        <String>{};

    for (final foto
        in canhotos) {
      notasComFoto.add(
        '${foto.movimentoId}|${foto.chaveNfe}',
      );
    }

    return _StatusCanhotos(
      totalNotas:
          viagem.totalNotas,
      notasComFoto:
          notasComFoto.length,
      totalFotos:
          canhotos.length,
      fotosEnviadas:
          canhotos
              .where(
                (foto) =>
                    foto.enviado,
              )
              .length,
    );
  }
}


class _StatusCanhotoCompacto
    extends StatelessWidget {
  final _StatusCanhotos status;

  const _StatusCanhotoCompacto({
    required this.status,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    if (status.totalFotos ==
        0) {
      return const Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            Icons.no_photography_outlined,
            size: 14,
            color:
                Colors.grey,
          ),
          SizedBox(
            width: 4,
          ),
          Text(
            'Sem canhotos',
            style:
                TextStyle(
              fontSize:
                  11,
              color:
                  Colors.grey,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final tudoEnviado =
        status.fotosPendentes ==
            0;

    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        Icon(
          tudoEnviado
              ? Icons.cloud_done
              : Icons.cloud_upload_outlined,
          size:
              14,
          color:
              tudoEnviado
                  ? Colors.green
                  : Colors.orange,
        ),

        const SizedBox(
          width: 4,
        ),

        Text(
          tudoEnviado
              ? '${status.fotosEnviadas}/${status.totalFotos} fotos enviadas'
              : '${status.fotosEnviadas}/${status.totalFotos} enviadas • ${status.fotosPendentes} pendente(s)',
          style:
              TextStyle(
            fontSize:
                11,
            color:
                tudoEnviado
                    ? Colors.green
                    : Colors.orange,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ],
    );
  }
}


class _LinhaInfo
    extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool destaque;
  final Color? corValor;

  const _LinhaInfo({
    required this.titulo,
    required this.valor,
    this.destaque = false,
    this.corValor,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child:
          Row(
        children: [
          Expanded(
            child:
                Text(
              titulo,
              style:
                  TextStyle(
                fontWeight:
                    destaque
                        ? FontWeight.bold
                        : FontWeight.normal,
              ),
            ),
          ),

          Text(
            valor,
            style:
                TextStyle(
              color:
                  corValor,
              fontWeight:
                  destaque ||
                          corValor !=
                              null
                      ? FontWeight.bold
                      : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
