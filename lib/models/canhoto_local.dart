class CanhotoLocal {
  final String id;

  final String viagemId;
  final String movimentoId;

  final String chaveNfe;
  final String numeroNfe;

  final String motorista;
  final String? cliente;
  final String cidade;
  final String tipoMovimento;

  final String localPath;
  final String? storagePath;

  final String statusSync;

  final DateTime capturadoEm;

  final int tentativas;
  final String? erroSync;

  const CanhotoLocal({
    required this.id,
    required this.viagemId,
    required this.movimentoId,
    required this.chaveNfe,
    required this.numeroNfe,
    required this.motorista,
    required this.cliente,
    required this.cidade,
    required this.tipoMovimento,
    required this.localPath,
    required this.storagePath,
    required this.statusSync,
    required this.capturadoEm,
    required this.tentativas,
    required this.erroSync,
  });

  bool get enviado =>
      statusSync == 'ENVIADO';

  bool get pendente =>
      statusSync == 'PENDENTE' ||
      statusSync == 'ERRO';

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'viagem_id': viagemId,
      'movimento_id': movimentoId,
      'chave_nfe': chaveNfe,
      'numero_nfe': numeroNfe,
      'motorista': motorista,
      'cliente': cliente,
      'cidade': cidade,
      'tipo_movimento': tipoMovimento,
      'local_path': localPath,
      'storage_path': storagePath,
      'status_sync': statusSync,
      'capturado_em':
          capturadoEm.toIso8601String(),
      'tentativas': tentativas,
      'erro_sync': erroSync,
      'updated_at':
          DateTime.now().toIso8601String(),
    };
  }

  factory CanhotoLocal.fromDbMap(
    Map<String, Object?> map,
  ) {
    return CanhotoLocal(
      id:
          map['id']?.toString() ?? '',
      viagemId:
          map['viagem_id']?.toString() ?? '',
      movimentoId:
          map['movimento_id']?.toString() ?? '',
      chaveNfe:
          map['chave_nfe']?.toString() ?? '',
      numeroNfe:
          map['numero_nfe']?.toString() ?? '',
      motorista:
          map['motorista']?.toString() ?? '',
      cliente:
          _textoOuNull(map['cliente']),
      cidade:
          map['cidade']?.toString() ?? '',
      tipoMovimento:
          map['tipo_movimento']?.toString() ??
              '',
      localPath:
          map['local_path']?.toString() ?? '',
      storagePath:
          _textoOuNull(map['storage_path']),
      statusSync:
          map['status_sync']?.toString() ??
              'PENDENTE',
      capturadoEm:
          DateTime.tryParse(
                map['capturado_em']
                        ?.toString() ??
                    '',
              ) ??
              DateTime.now(),
      tentativas:
          int.tryParse(
                map['tentativas']
                        ?.toString() ??
                    '',
              ) ??
              0,
      erroSync:
          _textoOuNull(map['erro_sync']),
    );
  }

  static String? _textoOuNull(
    dynamic valor,
  ) {
    final texto =
        valor?.toString().trim();

    if (texto == null ||
        texto.isEmpty) {
      return null;
    }

    return texto;
  }
}
