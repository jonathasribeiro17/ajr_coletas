import 'dart:developer' as developer;

import '../models/cidade_empresa_cadastro.dart';
import 'database_service.dart';
import 'supabase_service.dart';

class CadastroDestinoService {
  static final CadastroDestinoService instance =
      CadastroDestinoService._();

  CadastroDestinoService._();

  Future<List<CidadeEmpresaCadastro>>
      carregarCatalogo() async {
    await sincronizarPendentes();

    try {
      final remoto =
          await SupabaseService.instance
              .buscarCidadesEmpresas();

      await DatabaseService.instance
          .substituirCacheCidadeEmpresas(
        remoto,
      );
    } catch (e) {
      developer.log(
        'Sem conexão para atualizar cidades/empresas. '
        'Usando cache local.',
        name: 'CadastroDestinoService',
        error: e,
      );
    }

    final local =
        await DatabaseService.instance
            .buscarCacheCidadeEmpresas();

    return local
        .map(
          (item) =>
              CidadeEmpresaCadastro.fromMap(
            item,
          ),
        )
        .where(
          (item) =>
              item.cidadeNome.trim().isNotEmpty,
        )
        .toList();
  }

  Future<void> registrarUso({
    required String cidade,
    required String empresa,
  }) async {
    final cidadeFinal = cidade.trim();
    final empresaFinal = empresa.trim();

    if (cidadeFinal.isEmpty ||
        empresaFinal.isEmpty) {
      return;
    }

    // Primeiro salva no celular.
    // Assim o motorista não depende de internet.
    await DatabaseService.instance
        .salvarCadastroDestinoLocal(
      cidade: cidadeFinal,
      empresa: empresaFinal,
      pendenteSync: true,
    );

    try {
      final remoto =
          await SupabaseService.instance
              .registrarCidadeEmpresa(
        cidade: cidadeFinal,
        empresa: empresaFinal,
      );

      if (remoto == null) {
        return;
      }

      await DatabaseService.instance
          .marcarCadastroDestinoSincronizado(
        cidade: cidadeFinal,
        empresa: empresaFinal,
        cidadeId:
            remoto['cidade_id']?.toString(),
        cidadeNome:
            remoto['cidade_nome']?.toString(),
        empresaId:
            remoto['empresa_id']?.toString(),
        empresaNome:
            remoto['empresa_nome']?.toString(),
      );
    } catch (e) {
      developer.log(
        'Cadastro cidade/empresa ficou pendente '
        'para sincronização.',
        name: 'CadastroDestinoService',
        error: e,
      );
    }
  }

  Future<void> sincronizarPendentes() async {
    final pendentes =
        await DatabaseService.instance
            .buscarCadastrosDestinoPendentes();

    if (pendentes.isEmpty) {
      return;
    }

    for (final item in pendentes) {
      final cidade =
          item['cidade_nome']
                  ?.toString()
                  .trim() ??
              '';

      final empresa =
          item['empresa_nome']
                  ?.toString()
                  .trim() ??
              '';

      if (cidade.isEmpty ||
          empresa.isEmpty) {
        continue;
      }

      try {
        final remoto =
            await SupabaseService.instance
                .registrarCidadeEmpresa(
          cidade: cidade,
          empresa: empresa,
        );

        if (remoto == null) {
          continue;
        }

        await DatabaseService.instance
            .marcarCadastroDestinoSincronizado(
          cidade: cidade,
          empresa: empresa,
          cidadeId:
              remoto['cidade_id']?.toString(),
          cidadeNome:
              remoto['cidade_nome']?.toString(),
          empresaId:
              remoto['empresa_id']?.toString(),
          empresaNome:
              remoto['empresa_nome']?.toString(),
        );
      } catch (_) {
        // Se não houver internet, deixa pendente.
        // Uma próxima abertura da tela tenta novamente.
        break;
      }
    }
  }
}
