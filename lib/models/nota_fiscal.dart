class NotaFiscal {
  final String chave;
  final DateTime dataLeitura;

  final String? destinatarioNome;
  final String? destinatarioCnpj;
  final String? destinatarioEndereco;
  final String? destinatarioMunicipio;
  final String? destinatarioUf;

  final String? recebedorCnpj;
  final String? enderecoEntrega;

  NotaFiscal({
    required this.chave,
    required this.dataLeitura,
    this.destinatarioNome,
    this.destinatarioCnpj,
    this.destinatarioEndereco,
    this.destinatarioMunicipio,
    this.destinatarioUf,
    this.recebedorCnpj,
    this.enderecoEntrega,
  });

  static String limparChave(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  static String limparCnpj(String? valor) {
    if (valor == null) {
      return '';
    }

    return valor.replaceAll(RegExp(r'\D'), '');
  }

  static String formatarCnpj(String? valor) {
    final cnpj = limparCnpj(valor);

    if (cnpj.length != 14) {
      return valor ?? '';
    }

    return '${cnpj.substring(0, 2)}.'
        '${cnpj.substring(2, 5)}.'
        '${cnpj.substring(5, 8)}/'
        '${cnpj.substring(8, 12)}-'
        '${cnpj.substring(12, 14)}';
  }

  static bool validarChaveNfe(String chaveOriginal) {
    final chave = limparChave(chaveOriginal);

    if (chave.length != 44) {
      return false;
    }

    if (RegExp(r'^(\d)\1{43}$').hasMatch(chave)) {
      return false;
    }

    final base = chave.substring(0, 43);

    final dvInformado = int.tryParse(
      chave.substring(43, 44),
    );

    if (dvInformado == null) {
      return false;
    }

    int soma = 0;
    int peso = 2;

    for (int i = base.length - 1; i >= 0; i--) {
      soma += int.parse(base[i]) * peso;

      peso++;

      if (peso > 9) {
        peso = 2;
      }
    }

    final resto = soma % 11;

    int dvCalculado = 11 - resto;

    if (dvCalculado >= 10) {
      dvCalculado = 0;
    }

    return dvCalculado == dvInformado;
  }

  String get numeroNfe {
    final numeros = limparChave(chave);

    if (numeros.length != 44) {
      return '';
    }

    return numeros.substring(25, 34);
  }

  String get numeroNfeFormatado {
    final numero = numeroNfe;

    if (numero.isEmpty) {
      return 'Não identificado';
    }

    return numero;
  }

  String? get localEntrega {
    final complementar = enderecoEntrega?.trim();

    if (complementar != null &&
        complementar.isNotEmpty) {
      return complementar;
    }

    final principal = destinatarioEndereco?.trim();

    if (principal != null &&
        principal.isNotEmpty) {
      return principal;
    }

    return null;
  }

  bool get possuiDadosPmz {
    return limparCnpj(destinatarioCnpj).length == 14 &&
        localEntrega != null &&
        localEntrega!.trim().isNotEmpty;
  }

  String? get chaveAgrupamentoCte {
    final cnpj = limparCnpj(destinatarioCnpj);

    final local = localEntrega
        ?.trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), ' ');

    if (cnpj.length != 14 ||
        local == null ||
        local.isEmpty) {
      return null;
    }

    return '$cnpj|$local';
  }

  Map<String, dynamic> toMap() {
    return {
      'chave': chave,
      'dataLeitura': dataLeitura.toIso8601String(),
      'destinatarioNome': destinatarioNome,
      'destinatarioCnpj': destinatarioCnpj,
      'destinatarioEndereco': destinatarioEndereco,
      'destinatarioMunicipio': destinatarioMunicipio,
      'destinatarioUf': destinatarioUf,
      'recebedorCnpj': recebedorCnpj,
      'enderecoEntrega': enderecoEntrega,
    };
  }

  factory NotaFiscal.fromMap(
    Map<String, dynamic> map,
  ) {
    return NotaFiscal(
      chave: map['chave'] as String,
      dataLeitura: DateTime.parse(
        map['dataLeitura'] as String,
      ),
      destinatarioNome:
          map['destinatarioNome'] as String?,
      destinatarioCnpj:
          map['destinatarioCnpj'] as String?,
      destinatarioEndereco:
          map['destinatarioEndereco'] as String?,
      destinatarioMunicipio:
          map['destinatarioMunicipio'] as String?,
      destinatarioUf:
          map['destinatarioUf'] as String?,
      recebedorCnpj:
          map['recebedorCnpj'] as String?,
      enderecoEntrega:
          map['enderecoEntrega'] as String?,
    );
  }

  NotaFiscal copyWith({
    String? chave,
    DateTime? dataLeitura,
    String? destinatarioNome,
    String? destinatarioCnpj,
    String? destinatarioEndereco,
    String? destinatarioMunicipio,
    String? destinatarioUf,
    String? recebedorCnpj,
    String? enderecoEntrega,
    bool limparRecebedor = false,
    bool limparEntrega = false,
  }) {
    return NotaFiscal(
      chave: chave ?? this.chave,
      dataLeitura:
          dataLeitura ?? this.dataLeitura,
      destinatarioNome:
          destinatarioNome ??
              this.destinatarioNome,
      destinatarioCnpj:
          destinatarioCnpj ??
              this.destinatarioCnpj,
      destinatarioEndereco:
          destinatarioEndereco ??
              this.destinatarioEndereco,
      destinatarioMunicipio:
          destinatarioMunicipio ??
              this.destinatarioMunicipio,
      destinatarioUf:
          destinatarioUf ??
              this.destinatarioUf,
      recebedorCnpj: limparRecebedor
          ? null
          : recebedorCnpj ??
              this.recebedorCnpj,
      enderecoEntrega: limparEntrega
          ? null
          : enderecoEntrega ??
              this.enderecoEntrega,
    );
  }
}