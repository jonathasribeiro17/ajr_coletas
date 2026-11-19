class CidadeEmpresaCadastro {
  final String? cidadeId;
  final String cidadeNome;

  final String? empresaId;
  final String empresaNome;

  final int quantidadeUso;
  final DateTime? ultimoUsoEm;

  const CidadeEmpresaCadastro({
    required this.cidadeId,
    required this.cidadeNome,
    required this.empresaId,
    required this.empresaNome,
    required this.quantidadeUso,
    required this.ultimoUsoEm,
  });

  bool get temEmpresa =>
      empresaNome.trim().isNotEmpty;

  factory CidadeEmpresaCadastro.fromMap(
    Map<String, dynamic> map,
  ) {
    final ultimoUsoRaw =
        map['ultimo_uso_em']?.toString();

    return CidadeEmpresaCadastro(
      cidadeId:
          _textoOuNull(map['cidade_id']),
      cidadeNome:
          map['cidade_nome']
                  ?.toString()
                  .trim() ??
              '',
      empresaId:
          _textoOuNull(map['empresa_id']),
      empresaNome:
          map['empresa_nome']
                  ?.toString()
                  .trim() ??
              '',
      quantidadeUso:
          _inteiro(map['quantidade_uso']),
      ultimoUsoEm:
          ultimoUsoRaw == null ||
                  ultimoUsoRaw.isEmpty
              ? null
              : DateTime.tryParse(
                  ultimoUsoRaw,
                )?.toLocal(),
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

  static int _inteiro(
    dynamic valor,
  ) {
    if (valor is int) {
      return valor;
    }

    return int.tryParse(
          valor?.toString() ?? '',
        ) ??
        0;
  }
}
