import 'movimento.dart';

class Viagem {
  final String id;
  final String motorista;
  final String destino;
  final String? cliente;
  final DateTime dataInicio;
  final DateTime? dataFim;
  final String status;
  final bool sincronizada;
  final List<Movimento> movimentos;

  Viagem({
    required this.id,
    required this.motorista,
    required this.destino,
    this.cliente,
    required this.dataInicio,
    this.dataFim,
    required this.status,
    this.sincronizada = false,
    required this.movimentos,
  });

  int get totalNotas {
    return movimentos.fold(
      0,
      (total, movimento) => total + movimento.notas.length,
    );
  }

  int get totalNotasIda {
    return movimentos
        .where(
          (movimento) => movimento.tipo == TipoMovimento.ida,
        )
        .fold(
          0,
          (total, movimento) => total + movimento.notas.length,
        );
  }

  int get totalNotasRetorno {
    return movimentos
        .where(
          (movimento) => movimento.tipo == TipoMovimento.retorno,
        )
        .fold(
          0,
          (total, movimento) => total + movimento.notas.length,
        );
  }

  int get totalNotasAcrescimo {
    return movimentos
        .where(
          (movimento) => movimento.tipo == TipoMovimento.acrescimo,
        )
        .fold(
          0,
          (total, movimento) => total + movimento.notas.length,
        );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'motorista': motorista,
      'destino': destino,
      'cliente': cliente,
      'dataInicio': dataInicio.toIso8601String(),
      'dataFim': dataFim?.toIso8601String(),
      'status': status,
      'sincronizada': sincronizada,
      'movimentos':
          movimentos.map((movimento) => movimento.toMap()).toList(),
    };
  }

  factory Viagem.fromMap(Map<String, dynamic> map) {
    return Viagem(
      id: map['id'] as String,
      motorista: map['motorista'] as String,
      destino: map['destino'] as String,
      cliente: map['cliente'] as String?,
      dataInicio: DateTime.parse(
        map['dataInicio'] as String,
      ),
      dataFim: map['dataFim'] != null
          ? DateTime.parse(
              map['dataFim'] as String,
            )
          : null,
      status: map['status'] as String,
      sincronizada: map['sincronizada'] == true ||
          map['sincronizada'] == 1,
      movimentos: (map['movimentos'] as List<dynamic>)
          .map(
            (movimento) => Movimento.fromMap(
              Map<String, dynamic>.from(movimento as Map),
            ),
          )
          .toList(),
    );
  }
}