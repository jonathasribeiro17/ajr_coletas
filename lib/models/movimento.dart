import 'nota_fiscal.dart';

enum TipoMovimento {
  ida,
  retorno,
  acrescimo,
}

class Movimento {
  final String id;
  final String viagemId;
  final TipoMovimento tipo;

  // NOVO:
  // usado principalmente para identificar
  // o cliente de cada acréscimo
  final String? cliente;

  final DateTime dataHora;
  final List<NotaFiscal> notas;

  Movimento({
    required this.id,
    required this.viagemId,
    required this.tipo,
    this.cliente,
    required this.dataHora,
    required this.notas,
  });

  String get tipoTexto {
    switch (tipo) {
      case TipoMovimento.ida:
        return 'IDA';

      case TipoMovimento.retorno:
        return 'RETORNO';

      case TipoMovimento.acrescimo:
        return 'ACRESCIMO';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'viagemId': viagemId,
      'tipo': tipoTexto,

      // NOVO
      'cliente': cliente,

      'dataHora': dataHora.toIso8601String(),

      'notas': notas
          .map(
            (nota) => nota.toMap(),
          )
          .toList(),
    };
  }

  factory Movimento.fromMap(
    Map<String, dynamic> map,
  ) {
    TipoMovimento tipo;

    switch (
        (map['tipo'] as String).toUpperCase()) {
      case 'RETORNO':
        tipo = TipoMovimento.retorno;
        break;

      case 'ACRESCIMO':
        tipo = TipoMovimento.acrescimo;
        break;

      default:
        tipo = TipoMovimento.ida;
    }

    return Movimento(
      id: map['id'] as String,

      viagemId:
          map['viagemId'] as String,

      tipo:
          tipo,

      // NOVO
      cliente:
          map['cliente'] as String?,

      dataHora:
          DateTime.parse(
        map['dataHora'] as String,
      ),

      notas:
          (map['notas'] as List<dynamic>)
              .map(
        (nota) {
          return NotaFiscal.fromMap(
            Map<String, dynamic>.from(
              nota as Map,
            ),
          );
        },
      ).toList(),
    );
  }
}