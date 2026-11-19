import 'dart:developer' as developer;

import 'database_service.dart';
import 'supabase_service.dart';

class SyncService {
  static final SyncService instance =
      SyncService._();

  SyncService._();

  bool _sincronizando = false;

  bool get sincronizando =>
      _sincronizando;

  Future<int> sincronizarPendentes() async {
    if (_sincronizando) {
      return 0;
    }

    _sincronizando = true;

    int enviados = 0;

    try {
      final viagens =
          await DatabaseService.instance
              .buscarViagensPendentesSincronizacao();

      for (final viagem in viagens) {
        try {
          final sucesso =
              await SupabaseService.instance
                  .enviarViagem(
            viagem,
          );

          if (!sucesso) {
            continue;
          }

          await DatabaseService.instance
              .marcarViagemSincronizada(
            viagem.id,
          );

          enviados++;

          developer.log(
            'Sincronizada: ${viagem.id}',
            name: 'SyncService',
          );
        } catch (e) {
          developer.log(
            'Erro na viagem ${viagem.id}',
            name: 'SyncService',
            error: e,
          );
        }
      }
    } catch (e) {
      developer.log(
        'Erro ao sincronizar pendentes',
        name: 'SyncService',
        error: e,
      );
    } finally {
      _sincronizando = false;
    }

    return enviados;
  }

  Future<bool> sincronizarViagem(
    String viagemId,
  ) async {
    if (_sincronizando) {
      return false;
    }

    _sincronizando = true;

    try {
      final viagem =
          await DatabaseService.instance
              .buscarViagemPorId(
        viagemId,
      );

      if (viagem == null) {
        return false;
      }

      final sucesso =
          await SupabaseService.instance
              .enviarViagem(
        viagem,
      );

      if (!sucesso) {
        return false;
      }

      await DatabaseService.instance
          .marcarViagemSincronizada(
        viagem.id,
      );

      return true;
    } catch (e) {
      developer.log(
        'Erro ao sincronizar viagem $viagemId',
        name: 'SyncService',
        error: e,
      );

      return false;
    } finally {
      _sincronizando = false;
    }
  }
}