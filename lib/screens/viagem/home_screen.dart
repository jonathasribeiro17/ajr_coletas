import 'package:flutter/material.dart';

import '../../models/viagem.dart';
import '../../models/app_update.dart';
import '../../services/app_update_service.dart';
import '../../services/canhoto_sync_service.dart';
import '../../services/database_service.dart';
import '../viagem/historico_viagens_screen.dart';
import '../viagem/nova_viagem_screen.dart';
import '../viagem/viagem_screen.dart';
import '../../services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  final String nomeMotorista;

  const HomeScreen({
    super.key,
    required this.nomeMotorista,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Viagem? _viagemAberta;
  AppUpdate? _atualizacao;
  bool _carregando = true;
  Future<void> _inicializarHome() async {
    await SyncService.instance
        .sincronizarPendentes();

    await CanhotoSyncService.instance
        .sincronizarPendentesFinalizados();

    await _carregarViagemAberta();
  }

  @override
  void initState() {
    super.initState();
    _inicializarHome();
    _verificarAtualizacao();
  }

  Future<void> _verificarAtualizacao() async {
    try {
      final atualizacao = await AppUpdateService.instance
          .buscarAtualizacaoDisponivel();
      if (mounted) setState(() => _atualizacao = atualizacao);
    } catch (_) {
      // Falha de rede ou atualização ainda não configurada não atrapalha o app.
    }
  }

  Future<void> _baixarAtualizacao(AppUpdate atualizacao) async {
    var baixando = false;
    var recebido = 0;
    int? total;
    String? erro;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (contextoDialogo) => StatefulBuilder(
        builder: (contexto, atualizarDialogo) {
          final percentual = total == null || total == 0
              ? null
              : recebido / total!;
          return AlertDialog(
            title: Text(baixando ? 'Baixando atualização' : 'Atualizar AJR Coletas'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Versão ${atualizacao.versionName} disponível.'),
                if ((atualizacao.observacao ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(atualizacao.observacao!),
                ],
                if (baixando) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(value: percentual),
                  const SizedBox(height: 8),
                  Text(percentual == null
                      ? 'Baixando...'
                      : '${(percentual * 100).toStringAsFixed(0)}%'),
                ],
                if (erro != null) ...[
                  const SizedBox(height: 12),
                  Text(erro!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              if (!baixando)
                TextButton(
                  onPressed: () => Navigator.pop(contexto),
                  child: const Text('DEPOIS'),
                ),
              FilledButton.icon(
                onPressed: baixando
                    ? null
                    : () async {
                        atualizarDialogo(() {
                          baixando = true;
                          erro = null;
                        });
                        try {
                          await AppUpdateService.instance.baixarEInstalar(
                            atualizacao,
                            onProgress: (novoRecebido, novoTotal) {
                              if (contexto.mounted) {
                                atualizarDialogo(() {
                                  recebido = novoRecebido;
                                  total = novoTotal;
                                });
                              }
                            },
                          );
                        } catch (e) {
                          if (contexto.mounted) {
                            atualizarDialogo(() {
                              baixando = false;
                              erro = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.system_update_alt),
                label: Text(baixando ? 'AGUARDE' : 'BAIXAR E INSTALAR'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _carregarViagemAberta() async {
    final viagem = await DatabaseService.instance.buscarViagemAberta(
      widget.nomeMotorista,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _viagemAberta = viagem;
      _carregando = false;
    });
  }

  Future<void> _novaViagem() async {
    if (_viagemAberta != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finalize a viagem em andamento antes de iniciar outra.',
          ),
        ),
      );

      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NovaViagemScreen(
          nomeMotorista: widget.nomeMotorista,
        ),
      ),
    );

    await _carregarViagemAberta();
  }

  Future<void> _continuarViagem() async {
    final viagem = _viagemAberta;

    if (viagem == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViagemScreen(
          viagem: viagem,
        ),
      ),
    );

    await _carregarViagemAberta();
  }

  Future<void> _abrirHistorico() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoricoViagensScreen(
          nomeMotorista: widget.nomeMotorista,
        ),
      ),
    );

    await _carregarViagemAberta();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'AJR Coletas',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _inicializarHome,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Image.asset(
                'assets/images/ajr_logo_transparente.png',
                width: 170,
                height: 110,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Olá, ${widget.nomeMotorista}! 👋',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              _viagemAberta == null
                  ? 'Nenhuma viagem em andamento.'
                  : 'Você possui uma viagem em andamento.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 24),

            if (_carregando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(25),
                  child: CircularProgressIndicator(),
                ),
              ),

            if (!_carregando && _viagemAberta != null)
              _ViagemAbertaCard(
                viagem: _viagemAberta!,
                onContinuar: _continuarViagem,
              ),

            if (!_carregando && _viagemAberta != null)
              const SizedBox(height: 18),

            if (_atualizacao != null) ...[
              _AtualizacaoDisponivelCard(
                atualizacao: _atualizacao!,
                onAtualizar: () => _baixarAtualizacao(_atualizacao!),
              ),
              const SizedBox(height: 14),
            ],

            _MenuButton(
              icon: Icons.add_road,
              title: 'NOVA VIAGEM',
              subtitle: _viagemAberta == null
                  ? 'Selecionar destino e iniciar viagem'
                  : 'Finalize a viagem atual para iniciar outra',
              color: _viagemAberta == null
                  ? theme.colorScheme.primary
                  : Colors.grey,
              onPressed: _novaViagem,
            ),

            const SizedBox(height: 14),

            _MenuButton(
              icon: Icons.history,
              title: 'MINHAS VIAGENS',
              subtitle: 'Consultar viagens já realizadas',
              color: Colors.teal,
              onPressed: _abrirHistorico,
            ),

            const SizedBox(height: 30),

            const Center(
              child: Text(
                'AJR Transportes',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 4),

            const Center(
              child: Text(
                'Versão 1.0.0',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViagemAbertaCard extends StatelessWidget {
  final Viagem viagem;
  final VoidCallback onContinuar;

  const _ViagemAbertaCard({
    required this.viagem,
    required this.onContinuar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_shipping,
                color: theme.colorScheme.primary,
                size: 30,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'VIAGEM EM ANDAMENTO',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'ABERTA',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            viagem.destino,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (viagem.cliente != null) ...[
            const SizedBox(height: 4),
            Text(
              viagem.cliente!,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              _ResumoItem(
                titulo: 'IDA',
                quantidade: viagem.totalNotasIda,
              ),
              _ResumoItem(
                titulo: 'RETORNO',
                quantidade: viagem.totalNotasRetorno,
              ),
              _ResumoItem(
                titulo: 'ACRÉSCIMO',
                quantidade: viagem.totalNotasAcrescimo,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Text(
                'Total de NF-es:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${viagem.totalNotas}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onContinuar,
              icon: const Icon(
                Icons.play_arrow,
              ),
              label: const Text(
                'CONTINUAR VIAGEM',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoItem extends StatelessWidget {
  final String titulo;
  final int quantidade;

  const _ResumoItem({
    required this.titulo,
    required this.quantidade,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$quantidade',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AtualizacaoDisponivelCard extends StatelessWidget {
  final AppUpdate atualizacao;
  final VoidCallback onAtualizar;

  const _AtualizacaoDisponivelCard({
    required this.atualizacao,
    required this.onAtualizar,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onAtualizar,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.system_update_alt, color: Color(0xFF2563EB), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ATUALIZAÇÃO DISPONÍVEL',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                    const SizedBox(height: 3),
                    Text('Versão ${atualizacao.versionName} • Toque para atualizar'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF2563EB)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onPressed;

  const _MenuButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 88,
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 30,
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
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
