import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/viagem.dart';

class SupabaseService {
  static final SupabaseService instance =
      SupabaseService._();

  SupabaseService._();

  SupabaseClient get _client =>
      Supabase.instance.client;

  // ============================================================
  // VIAGEM
  // ============================================================

  Future<bool> enviarViagem(
    Viagem viagem,
  ) async {
    try {
      final dados = {
        'id':
            viagem.id,
        'motorista':
            viagem.motorista,
        'destino':
            viagem.destino,
        'cliente':
            viagem.cliente,
        'dataInicio':
            viagem.dataInicio
                .toIso8601String(),
        'dataFim':
            viagem.dataFim
                ?.toIso8601String(),
        'status':
            viagem.status,
        'movimentos':
            viagem.movimentos.map(
          (movimento) {
            return {
              'id':
                  movimento.id,
              'viagemId':
                  movimento.viagemId,
              'tipo':
                  movimento.tipoTexto,
              'cliente':
                  movimento.cliente,
              'dataHora':
                  movimento.dataHora
                      .toIso8601String(),
              'notas':
                  movimento.notas.map(
                (nota) {
                  return {
                    'chave':
                        nota.chave,
                    'numero':
                        nota.numeroNfeFormatado,
                    'dataLeitura':
                        nota.dataLeitura
                            .toIso8601String(),
                    'destinatarioNome':
                        nota.destinatarioNome,
                    'destinatarioCnpj':
                        nota.destinatarioCnpj,
                    'destinatarioEndereco':
                        nota.destinatarioEndereco,
                    'destinatarioMunicipio':
                        nota.destinatarioMunicipio,
                    'destinatarioUf':
                        nota.destinatarioUf,
                    'recebedorCnpj':
                        nota.recebedorCnpj,
                    'enderecoEntrega':
                        nota.enderecoEntrega,
                  };
                },
              ).toList(),
            };
          },
        ).toList(),
      };

      await _client.rpc(
        'sincronizar_viagem',
        params: {
          'p_viagem': dados,
        },
      );

      return true;
    } catch (e) {
      developer.log(
        'Erro ao sincronizar viagem',
        name: 'SupabaseService',
        error: e,
      );

      return false;
    }
  }

  // ============================================================
  // CIDADES / EMPRESAS
  // ============================================================

  Future<List<Map<String, dynamic>>>
      buscarCidadesEmpresas() async {
    final resposta =
        await _client.rpc(
      'listar_cidades_empresas',
    );

    if (resposta is! List) {
      return [];
    }

    return resposta
        .whereType<Map>()
        .map(
          (item) =>
              Map<String, dynamic>.from(
            item,
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>?>
      registrarCidadeEmpresa({
    required String cidade,
    required String empresa,
  }) async {
    final resposta =
        await _client.rpc(
      'registrar_cidade_empresa',
      params: {
        'p_cidade': cidade.trim(),
        'p_empresa': empresa.trim(),
      },
    );

    if (resposta is List &&
        resposta.isNotEmpty &&
        resposta.first is Map) {
      return Map<String, dynamic>.from(
        resposta.first as Map,
      );
    }

    if (resposta is Map) {
      return Map<String, dynamic>.from(
        resposta,
      );
    }

    return null;
  }
}
