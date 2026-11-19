import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DestinatarioOcr {
  final String? nome;
  final String? cnpj;
  final String? endereco;
  final String? municipio;
  final String? uf;

  final bool encontrouSecaoDestinatario;

  final int confianca;

  const DestinatarioOcr({
    this.nome,
    this.cnpj,
    this.endereco,
    this.municipio,
    this.uf,
    this.encontrouSecaoDestinatario = false,
    this.confianca = 0,
  });

  bool get cnpjValido {
    return DanfeOcrService.validarCnpj(
      cnpj,
    );
  }

  bool get ufValida {
    return DanfeOcrService.validarUf(
      uf,
    );
  }

  bool get completo {
    return encontrouSecaoDestinatario &&
        nome != null &&
        nome!.trim().isNotEmpty &&
        cnpjValido &&
        endereco != null &&
        endereco!.trim().isNotEmpty &&
        municipio != null &&
        municipio!.trim().isNotEmpty &&
        ufValida;
  }

  String get nivelConfianca {
    if (confianca >= 85) {
      return 'ALTA';
    }

    if (confianca >= 60) {
      return 'MÉDIA';
    }

    return 'BAIXA';
  }
}

class ComplementarOcr {
  final String? cnpj;
  final String? endereco;

  const ComplementarOcr({
    this.cnpj,
    this.endereco,
  });
}

class DanfeOcrService {
  DanfeOcrService._();

  static final DanfeOcrService instance =
      DanfeOcrService._();

  final TextRecognizer _recognizer =
      TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  static const Set<String> _ufs = {
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO',
  };

  // ============================================================
  // DESTINATÁRIO
  // ============================================================

  Future<DestinatarioOcr> lerDestinatario(
    String caminhoImagem,
  ) async {
    final inputImage =
        InputImage.fromFilePath(
      caminhoImagem,
    );

    final reconhecido =
        await _recognizer.processImage(
      inputImage,
    );

    final todasLinhas =
        _obterLinhas(
      reconhecido,
    );

    if (todasLinhas.isEmpty) {
      return const DestinatarioOcr();
    }

    // ==========================================================
    // LOCALIZAR SEÇÃO DESTINATÁRIO
    // ==========================================================

    _LinhaOcr? tituloDestinatario;

    for (final linha in todasLinhas) {
      final texto =
          _normalizar(
        linha.texto,
      );

      if (texto.contains(
            'DESTINATARIO',
          ) &&
          texto.contains(
            'REMETENTE',
          )) {
        tituloDestinatario =
            linha;

        break;
      }
    }

    // Se não achou DESTINATÁRIO/REMETENTE, não vamos fingir
    // que sabemos qual é o destinatário.
    if (tituloDestinatario == null) {
      return const DestinatarioOcr(
        encontrouSecaoDestinatario:
            false,
        confianca:
            0,
      );
    }

    // ==========================================================
    // LOCALIZAR FIM DA SEÇÃO
    // ==========================================================

    _LinhaOcr? fimSecao;

    for (final linha in todasLinhas) {
      if (linha.top <=
          tituloDestinatario.bottom) {
        continue;
      }

      final texto =
          _normalizar(
        linha.texto,
      );

      if (texto == 'FATURA' ||
          texto.startsWith(
            'FATURA ',
          ) ||
          texto.contains(
            'CALCULO DO IMPOSTO',
          ) ||
          texto.contains(
            'CALCULO DE IMPOSTO',
          ) ||
          texto.contains(
            'TRANSPORTADOR',
          )) {
        fimSecao =
            linha;

        break;
      }
    }

    final topo =
        tituloDestinatario.bottom;

    final limiteInferior =
        fimSecao?.top ??
            double.infinity;

    final linhasSecao =
        todasLinhas.where(
      (linha) {
        return linha.top >= topo &&
            linha.bottom <=
                limiteInferior;
      },
    ).toList();

    if (linhasSecao.isEmpty) {
      return const DestinatarioOcr(
        encontrouSecaoDestinatario:
            true,
        confianca:
            10,
      );
    }

    // ==========================================================
    // LOCALIZAR RÓTULOS
    // ==========================================================

    final rotuloNome =
        _buscarRotulo(
      linhasSecao,
      [
        'NOME/RAZAO SOCIAL',
        'NOME RAZAO SOCIAL',
        'RAZAO SOCIAL',
      ],
    );

    final rotuloCnpj =
        _buscarRotulo(
      linhasSecao,
      [
        'CNPJ/CPF',
        'CNPJ CPF',
        'CNPJ',
      ],
    );

    final rotuloEndereco =
        _buscarRotulo(
      linhasSecao,
      [
        'ENDERECO',
      ],
    );

    final rotuloMunicipio =
        _buscarRotulo(
      linhasSecao,
      [
        'MUNICIPIO',
      ],
    );

    final rotuloUf =
        _buscarRotulo(
      linhasSecao,
      [
        'UF',
      ],
    );

    // ==========================================================
    // NOME
    // ==========================================================

    String? nome;

    if (rotuloNome != null) {
      nome =
          _buscarValorNaColunaAbaixo(
        linhasSecao,
        rotuloNome,
        alturaMaxima:
            130,
        margemEsquerda:
            40,
        margemDireita:
            180,
        validar:
            (texto) {
          final normalizado =
              _normalizar(
            texto,
          );

          if (_ehRotulo(
            normalizado,
          )) {
            return false;
          }

          if (_extrairCnpj(
                texto,
              ) !=
              null) {
            return false;
          }

          return RegExp(
            r'[A-Za-zÀ-ÿ]',
          ).hasMatch(
            texto,
          );
        },
      );
    }

    // ==========================================================
    // CNPJ
    // ==========================================================

    String? cnpj;

    if (rotuloCnpj != null) {
      final candidatas =
          _linhasProximasDaColuna(
        linhasSecao,
        rotuloCnpj,
        alturaMaxima:
            140,
        margemEsquerda:
            60,
        margemDireita:
            160,
      );

      for (final linha
          in candidatas) {
        final encontrado =
            _extrairCnpj(
          linha.texto,
        );

        if (encontrado != null &&
            validarCnpj(
              encontrado,
            )) {
          cnpj =
              encontrado;

          break;
        }
      }
    }

    // Fallback: procura qualquer CNPJ válido,
    // mas somente dentro da seção DESTINATÁRIO.
    cnpj ??=
        _primeiroCnpjValido(
      linhasSecao,
    );

    // ==========================================================
    // ENDEREÇO
    // ==========================================================

    String? endereco;

    if (rotuloEndereco != null) {
      endereco =
          _buscarValorNaColunaAbaixo(
        linhasSecao,
        rotuloEndereco,
        alturaMaxima:
            130,
        margemEsquerda:
            50,
        margemDireita:
            260,
        validar:
            _pareceEndereco,
      );
    }

    endereco ??=
        _buscarEnderecoProvavel(
      linhasSecao,
    );

    // ==========================================================
    // MUNICÍPIO
    // ==========================================================

    String? municipio;

    if (rotuloMunicipio != null) {
      municipio =
          _buscarValorNaColunaAbaixo(
        linhasSecao,
        rotuloMunicipio,
        alturaMaxima:
            130,
        margemEsquerda:
            50,
        margemDireita:
            160,
        validar:
            (texto) {
          final valor =
              _normalizar(
            texto,
          );

          if (_ehRotulo(valor)) {
            return false;
          }

          if (_pareceTelefone(
            texto,
          )) {
            return false;
          }

          if (_extrairCnpj(
                texto,
              ) !=
              null) {
            return false;
          }

          return RegExp(
            r'[A-Za-zÀ-ÿ]',
          ).hasMatch(
            texto,
          );
        },
      );
    }

    // ==========================================================
    // UF
    // ==========================================================

    String? uf;

    if (rotuloUf != null) {
      final candidatas =
          _linhasProximasDaColuna(
        linhasSecao,
        rotuloUf,
        alturaMaxima:
            120,
        margemEsquerda:
            40,
        margemDireita:
            80,
      );

      for (final linha
          in candidatas) {
        final candidata =
            _extrairUf(
          linha.texto,
        );

        if (validarUf(
          candidata,
        )) {
          uf =
              candidata;

          break;
        }
      }
    }

    // ==========================================================
    // FALLBACK MUNICÍPIO / UF
    // ==========================================================

    if (municipio == null ||
        uf == null) {
      for (final linha
          in linhasSecao) {
        final local =
            _extrairMunicipioUf(
          linha.texto,
        );

        if (local == null) {
          continue;
        }

        municipio ??=
            local.$1;

        if (validarUf(
          local.$2,
        )) {
          uf ??=
              local.$2;
        }
      }
    }

    // ==========================================================
    // LIMPEZA
    // ==========================================================

    nome =
        _limparTexto(
      nome,
    );

    endereco =
        _limparTexto(
      endereco,
    );

    municipio =
        _limparTexto(
      municipio,
    );

    uf =
        _limparTexto(
      uf,
    )?.toUpperCase();

    // ==========================================================
    // CONFIANÇA
    // ==========================================================

    int confianca =
        20;

    if (rotuloNome != null) {
      confianca += 5;
    }

    if (rotuloCnpj != null) {
      confianca += 5;
    }

    if (rotuloEndereco != null) {
      confianca += 5;
    }

    if (rotuloMunicipio != null) {
      confianca += 5;
    }

    if (rotuloUf != null) {
      confianca += 5;
    }

    if (nome != null &&
        nome.isNotEmpty) {
      confianca += 15;
    }

    if (validarCnpj(
      cnpj,
    )) {
      confianca += 20;
    }

    if (endereco != null &&
        endereco.isNotEmpty &&
        _pareceEndereco(
          endereco,
        )) {
      confianca += 10;
    }

    if (municipio != null &&
        municipio.isNotEmpty) {
      confianca += 5;
    }

    if (validarUf(
      uf,
    )) {
      confianca += 5;
    }

    confianca =
        math.min(
      confianca,
      100,
    );

    return DestinatarioOcr(
      nome:
          nome,
      cnpj:
          cnpj,
      endereco:
          endereco,
      municipio:
          municipio,
      uf:
          uf,
      encontrouSecaoDestinatario:
          true,
      confianca:
          confianca,
    );
  }

  // ============================================================
  // COMPLEMENTARES
  // ============================================================

  Future<ComplementarOcr>
      lerComplementares(
    String caminhoImagem,
  ) async {
    final inputImage =
        InputImage.fromFilePath(
      caminhoImagem,
    );

    final reconhecido =
        await _recognizer.processImage(
      inputImage,
    );

    final linhas =
        _obterLinhas(
      reconhecido,
    );

    if (linhas.isEmpty) {
      return const ComplementarOcr();
    }

    String? cnpj;

    for (final linha
        in linhas) {
      final encontrado =
          _extrairCnpj(
        linha.texto,
      );

      if (encontrado != null &&
          validarCnpj(
            encontrado,
          )) {
        cnpj =
            encontrado;

        break;
      }
    }

    String? endereco;

    for (int i = 0;
        i < linhas.length;
        i++) {
      final linha =
          linhas[i];

      final normalizado =
          _normalizar(
        linha.texto,
      );

      final match =
          RegExp(
        r'\bEND\s*[:\-]',
      ).firstMatch(
        normalizado,
      );

      if (match == null) {
        continue;
      }

      final posicao =
          normalizado.indexOf(
        'END',
      );

      String valor =
          linha.texto.substring(
        math.min(
          posicao + 3,
          linha.texto.length,
        ),
      );

      valor = valor.replaceFirst(
        RegExp(
          r'^\s*[:\-]\s*',
        ),
        '',
      );

      final partes =
          <String>[];

      if (valor.trim().isNotEmpty) {
        partes.add(
          valor.trim(),
        );
      }

      for (int j = i + 1;
          j < linhas.length &&
              j <= i + 3;
          j++) {
        final proxima =
            linhas[j];

        if (_pareceNovoCampoComplementar(
          proxima.texto,
        )) {
          break;
        }

        partes.add(
          proxima.texto,
        );
      }

      final combinado =
          partes
              .join(' ')
              .replaceAll(
                RegExp(
                  r'\s+',
                ),
                ' ',
              )
              .trim();

      if (combinado.isNotEmpty) {
        endereco =
            combinado;
      }

      break;
    }

    return ComplementarOcr(
      cnpj:
          cnpj,
      endereco:
          endereco,
    );
  }

  // ============================================================
  // RÓTULO
  // ============================================================

  _LinhaOcr? _buscarRotulo(
    List<_LinhaOcr> linhas,
    List<String> rotulos,
  ) {
    for (final linha
        in linhas) {
      final texto =
          _normalizar(
        linha.texto,
      );

      for (final rotulo
          in rotulos) {
        if (texto == rotulo ||
            texto.contains(
              rotulo,
            )) {
          return linha;
        }
      }
    }

    return null;
  }

  // ============================================================
  // BUSCAR VALOR POR COLUNA
  // ============================================================

  String? _buscarValorNaColunaAbaixo(
    List<_LinhaOcr> linhas,
    _LinhaOcr rotulo, {
    required double alturaMaxima,
    required double margemEsquerda,
    required double margemDireita,
    required bool Function(
      String texto,
    ) validar,
  }) {
    final candidatas =
        _linhasProximasDaColuna(
      linhas,
      rotulo,
      alturaMaxima:
          alturaMaxima,
      margemEsquerda:
          margemEsquerda,
      margemDireita:
          margemDireita,
    );

    for (final candidata
        in candidatas) {
      if (validar(
        candidata.texto,
      )) {
        return candidata.texto;
      }
    }

    return null;
  }

  List<_LinhaOcr> _linhasProximasDaColuna(
    List<_LinhaOcr> linhas,
    _LinhaOcr rotulo, {
    required double alturaMaxima,
    required double margemEsquerda,
    required double margemDireita,
  }) {
    final centroRotulo =
        rotulo.centerX;

    final resultado =
        linhas.where(
      (linha) {
        if (linha == rotulo) {
          return false;
        }

        if (linha.top <
            rotulo.bottom - 10) {
          return false;
        }

        if (linha.top -
                rotulo.bottom >
            alturaMaxima) {
          return false;
        }

        final centro =
            linha.centerX;

        return centro >=
                rotulo.left -
                    margemEsquerda &&
            centro <=
                rotulo.right +
                    margemDireita &&
            (centro - centroRotulo)
                    .abs() <
                math.max(
                  rotulo.width +
                      margemDireita,
                  120,
                );
      },
    ).toList();

    resultado.sort(
      (a, b) {
        final distanciaYA =
            (a.top -
                    rotulo.bottom)
                .abs();

        final distanciaYB =
            (b.top -
                    rotulo.bottom)
                .abs();

        final compareY =
            distanciaYA.compareTo(
          distanciaYB,
        );

        if (compareY != 0) {
          return compareY;
        }

        final distanciaXA =
            (a.centerX -
                    rotulo.centerX)
                .abs();

        final distanciaXB =
            (b.centerX -
                    rotulo.centerX)
                .abs();

        return distanciaXA.compareTo(
          distanciaXB,
        );
      },
    );

    return resultado;
  }

  // ============================================================
  // CNPJ
  // ============================================================

  String? _primeiroCnpjValido(
    List<_LinhaOcr> linhas,
  ) {
    for (final linha
        in linhas) {
      final cnpj =
          _extrairCnpj(
        linha.texto,
      );

      if (cnpj != null &&
          validarCnpj(
            cnpj,
          )) {
        return cnpj;
      }
    }

    return null;
  }

  String? _extrairCnpj(
    String texto,
  ) {
    final regex =
        RegExp(
      r'(?<!\d)\d{2}\D{0,2}\d{3}\D{0,2}\d{3}\D{0,2}\d{4}\D{0,2}\d{2}(?!\d)',
    );

    for (final match
        in regex.allMatches(
      texto,
    )) {
      final numeros =
          match
              .group(0)
              ?.replaceAll(
                RegExp(
                  r'\D',
                ),
                '',
              );

      if (numeros != null &&
          numeros.length == 14) {
        return numeros;
      }
    }

    return null;
  }

  static bool validarCnpj(
    String? valor,
  ) {
    if (valor == null) {
      return false;
    }

    final cnpj =
        valor.replaceAll(
      RegExp(
        r'\D',
      ),
      '',
    );

    if (cnpj.length != 14) {
      return false;
    }

    if (RegExp(
      r'^(\d)\1{13}$',
    ).hasMatch(
      cnpj,
    )) {
      return false;
    }

    int calcularDv(
      String base,
      List<int> pesos,
    ) {
      int soma =
          0;

      for (int i = 0;
          i < base.length;
          i++) {
        soma +=
            int.parse(
                  base[i],
                ) *
                pesos[i];
      }

      final resto =
          soma % 11;

      return resto < 2
          ? 0
          : 11 - resto;
    }

    final primeiro =
        calcularDv(
      cnpj.substring(
        0,
        12,
      ),
      const [
        5,
        4,
        3,
        2,
        9,
        8,
        7,
        6,
        5,
        4,
        3,
        2,
      ],
    );

    if (primeiro !=
        int.parse(
          cnpj[12],
        )) {
      return false;
    }

    final segundo =
        calcularDv(
      cnpj.substring(
        0,
        13,
      ),
      const [
        6,
        5,
        4,
        3,
        2,
        9,
        8,
        7,
        6,
        5,
        4,
        3,
        2,
      ],
    );

    return segundo ==
        int.parse(
          cnpj[13],
        );
  }

  // ============================================================
  // UF
  // ============================================================

  String? _extrairUf(
    String texto,
  ) {
    final candidato =
        texto
            .replaceAll(
              RegExp(
                r'[^A-Za-z]',
              ),
              '',
            )
            .toUpperCase();

    if (candidato.length == 2 &&
        validarUf(
          candidato,
        )) {
      return candidato;
    }

    return null;
  }

  static bool validarUf(
    String? uf,
  ) {
    if (uf == null) {
      return false;
    }

    return _ufs.contains(
      uf.trim().toUpperCase(),
    );
  }

  // ============================================================
  // MUNICÍPIO / UF
  // ============================================================

  (String, String)? _extrairMunicipioUf(
    String texto,
  ) {
    final match =
        RegExp(
      r'([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ\s]{2,})\s*[/\-]\s*([A-Za-z]{2})\b',
    ).firstMatch(
      texto,
    );

    if (match == null) {
      return null;
    }

    final municipio =
        match
            .group(1)
            ?.trim();

    final uf =
        match
            .group(2)
            ?.trim()
            .toUpperCase();

    if (municipio == null ||
        municipio.isEmpty ||
        !validarUf(
          uf,
        )) {
      return null;
    }

    return (
      municipio,
      uf!,
    );
  }

  // ============================================================
  // ENDEREÇO
  // ============================================================

  String? _buscarEnderecoProvavel(
    List<_LinhaOcr> linhas,
  ) {
    for (final linha
        in linhas) {
      if (_pareceEndereco(
        linha.texto,
      )) {
        return linha.texto;
      }
    }

    return null;
  }

  bool _pareceEndereco(
    String texto,
  ) {
    final valor =
        _normalizar(
      texto,
    );

    const marcadores = [
      'RUA ',
      'R. ',
      'R ',
      'AV ',
      'AV. ',
      'AVENIDA ',
      'ROD ',
      'ROD. ',
      'RODOVIA ',
      'ESTRADA ',
      'TRAVESSA ',
      'ALAMEDA ',
      'PRACA ',
      'PCA ',
      'VIA ',
      'EST ',
    ];

    return marcadores.any(
      valor.startsWith,
    );
  }

  // ============================================================
  // TELEFONE
  // ============================================================

  bool _pareceTelefone(
    String texto,
  ) {
    final numeros =
        texto.replaceAll(
      RegExp(
        r'\D',
      ),
      '',
    );

    return numeros.length >= 8 &&
        numeros.length <= 13 &&
        (texto.contains(
              '(',
            ) ||
            texto.contains(
              ')',
            ) ||
            texto.contains(
              '-',
            ));
  }

  // ============================================================
  // COMPLEMENTARES
  // ============================================================

  bool _pareceNovoCampoComplementar(
    String texto,
  ) {
    final normalizado =
        _normalizar(
      texto,
    );

    const campos = [
      'PEDIDO:',
      'PED:',
      'VENDEDOR:',
      'OBS:',
      'VALOR:',
      'ICMS:',
      'NFE:',
      'NF-E:',
      'CHAVE:',
      'TRANSPORTADORA:',
    ];

    return campos.any(
      normalizado.startsWith,
    );
  }

  // ============================================================
  // LINHAS OCR
  // ============================================================

  List<_LinhaOcr> _obterLinhas(
    RecognizedText texto,
  ) {
    final linhas =
        <_LinhaOcr>[];

    for (final bloco
        in texto.blocks) {
      for (final linha
          in bloco.lines) {
        final valor =
            linha.text.trim();

        if (valor.isEmpty) {
          continue;
        }

        linhas.add(
          _LinhaOcr(
            texto:
                valor,
            left:
                linha.boundingBox.left,
            top:
                linha.boundingBox.top,
            right:
                linha.boundingBox.right,
            bottom:
                linha.boundingBox.bottom,
          ),
        );
      }
    }

    linhas.sort(
      (a, b) {
        final y =
            a.top.compareTo(
          b.top,
        );

        if (y != 0) {
          return y;
        }

        return a.left.compareTo(
          b.left,
        );
      },
    );

    return linhas;
  }

  // ============================================================
  // RÓTULOS
  // ============================================================

  bool _ehRotulo(
    String texto,
  ) {
    const rotulos = [
      'DESTINATARIO',
      'REMETENTE',
      'NOME',
      'RAZAO SOCIAL',
      'CNPJ',
      'CPF',
      'ENDERECO',
      'BAIRRO',
      'DISTRITO',
      'CEP',
      'MUNICIPIO',
      'FONE',
      'FAX',
      'UF',
      'INSCRICAO ESTADUAL',
      'DATA DA EMISSAO',
      'DATA DE SAIDA',
      'HORA DE SAIDA',
      'FATURA',
      'CALCULO DO IMPOSTO',
    ];

    return rotulos.any(
      (rotulo) =>
          texto == rotulo ||
          texto.contains(
            rotulo,
          ),
    );
  }

  // ============================================================
  // NORMALIZAÇÃO
  // ============================================================

  String _normalizar(
    String texto,
  ) {
    var valor =
        texto
            .trim()
            .toUpperCase();

    const mapa = {
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'É': 'E',
      'Ê': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ú': 'U',
      'Ç': 'C',
    };

    mapa.forEach(
      (origem, destino) {
        valor =
            valor.replaceAll(
          origem,
          destino,
        );
      },
    );

    return valor
        .replaceAll(
          RegExp(
            r'\s+',
          ),
          ' ',
        )
        .trim();
  }

  String? _limparTexto(
    String? valor,
  ) {
    if (valor == null) {
      return null;
    }

    final limpo =
        valor
            .replaceAll(
              RegExp(
                r'\s+',
              ),
              ' ',
            )
            .trim();

    if (limpo.isEmpty) {
      return null;
    }

    return limpo;
  }
}

// ============================================================
// LINHA OCR
// ============================================================

class _LinhaOcr {
  final String texto;

  final double left;
  final double top;
  final double right;
  final double bottom;

  const _LinhaOcr({
    required this.texto,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width {
    return right - left;
  }

  double get centerX {
    return left + (width / 2);
  }
}