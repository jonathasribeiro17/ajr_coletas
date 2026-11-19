import 'dart:async';
import 'dart:developer' as developer;

import '../models/canhoto_local.dart';
import 'database_service.dart';
import 'r2_canhoto_service.dart';

typedef CanhotoSyncProgress = void Function(
  int atual,
  int total,
  CanhotoLocal canhoto,
  String etapa,
);

class CanhotoSyncResumo {
  final int enviados;
  final int erros;
  final int pendentes;

  const CanhotoSyncResumo({
    required this.enviados,
    required this.erros,
    required this.pendentes,
  });
}

class CanhotoSyncService {
  static final CanhotoSyncService instance =
      CanhotoSyncService._();

  CanhotoSyncService._();

  bool _sincronizando = false;

  Future<CanhotoSyncResumo>
      sincronizarNoFechamento({
    required String viagemId,
    CanhotoSyncProgress? onProgress,
  }) async {
    if (_sincronizando) {
      final pendentes =
          await DatabaseService.instance
              .buscarCanhotosPendentesViagem(viagemId);

      return CanhotoSyncResumo(
        enviados: 0,
        erros: 0,
        pendentes: pendentes.length,
      );
    }

    _sincronizando = true;

    try {
      final pendentes =
          await DatabaseService.instance
              .buscarCanhotosPendentesViagem(viagemId);

      if (pendentes.isEmpty) {
        return const CanhotoSyncResumo(
          enviados: 0,
          erros: 0,
          pendentes: 0,
        );
      }

      int enviados = 0;
      int erros = 0;

      for (var i = 0; i < pendentes.length; i++) {
        final canhoto = pendentes[i];

        onProgress?.call(
          i + 1,
          pendentes.length,
          canhoto,
          'Enviando',
        );

        final sucesso =
            await _sincronizarUmComRetry(
          canhoto,
          onRetry: () {
            onProgress?.call(
              i + 1,
              pendentes.length,
              canhoto,
              'Tentando novamente',
            );
          },
        );

        if (sucesso) {
          enviados++;
          onProgress?.call(
            i + 1,
            pendentes.length,
            canhoto,
            'Enviado',
          );
        } else {
          erros++;
          onProgress?.call(
            i + 1,
            pendentes.length,
            canhoto,
            'Pendente',
          );
        }
      }

      final restantes =
          await DatabaseService.instance
              .buscarCanhotosPendentesViagem(viagemId);

      return CanhotoSyncResumo(
        enviados: enviados,
        erros: erros,
        pendentes: restantes.length,
      );
    } finally {
      _sincronizando = false;
    }
  }

  Future<void>
      sincronizarPendentesFinalizados() async {
    if (_sincronizando) {
      return;
    }

    final todos =
        await DatabaseService.instance
            .buscarCanhotosPendentes();

    final viagemIds =
        todos.map((e) => e.viagemId).toSet();

    for (final viagemId in viagemIds) {
      final viagem =
          await DatabaseService.instance
              .buscarViagemPorId(viagemId);

      if (viagem == null) {
        continue;
      }

      if (viagem.status.trim().toUpperCase() !=
          'FINALIZADA') {
        continue;
      }

      try {
        await sincronizarNoFechamento(
          viagemId: viagemId,
        );
      } catch (e) {
        developer.log(
          'Canhotos continuarão pendentes.',
          name: 'CanhotoSyncService',
          error: e,
        );
      }
    }
  }

  Future<bool> _sincronizarUmComRetry(
    CanhotoLocal canhoto, {
    required void Function() onRetry,
  }) async {
    Object? ultimoErro;

    for (var tentativa = 1;
        tentativa <= 2;
        tentativa++) {
      try {
        await DatabaseService.instance
            .marcarCanhotoEnviando(canhoto.id);

        final resultado =
            await R2CanhotoService.instance
                .enviar(canhoto)
                .timeout(
          const Duration(seconds: 28),
        );

        await DatabaseService.instance
            .marcarCanhotoEnviado(
          canhotoId: canhoto.id,
          storagePath: resultado.storagePath,
        );

        return true;
      } catch (e) {
        ultimoErro = e;

        developer.log(
          'Erro canhoto ${canhoto.numeroNfe}, '
          'tentativa $tentativa.',
          name: 'CanhotoSyncService',
          error: e,
        );

        if (tentativa < 2) {
          onRetry();
          await Future.delayed(
            const Duration(milliseconds: 900),
          );
        }
      }
    }

    await DatabaseService.instance
        .marcarCanhotoErro(
      canhotoId: canhoto.id,
      erro: _mensagemErro(
        ultimoErro ??
            Exception('Falha desconhecida.'),
      ),
    );

    return false;
  }

  String _mensagemErro(Object erro) {
    var texto = erro.toString().trim();

    if (texto.startsWith('Exception: ')) {
      texto = texto.substring(11);
    }

    if (texto.length > 500) {
      texto = texto.substring(0, 500);
    }

    return texto;
  }
}
