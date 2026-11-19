import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/canhoto_local.dart';
import '../models/movimento.dart';
import '../models/nota_fiscal.dart';
import '../models/viagem.dart';
import 'database_service.dart';

class CanhotoService {
  static final CanhotoService instance =
      CanhotoService._();

  CanhotoService._();

  final Random _random =
      Random.secure();

  Future<CanhotoLocal>
      salvarFotoCapturada({
    required String imagemPath,
    required Viagem viagem,
    required Movimento movimento,
    required NotaFiscal nota,
    bool removerArquivoOrigem = true,
  }) async {
    final origem =
        File(
      imagemPath,
    );

    if (!await origem.exists()) {
      throw Exception(
        'A foto não foi encontrada.',
      );
    }

    final agora =
        DateTime.now();

    final id =
        '${agora.microsecondsSinceEpoch}_'
        '${_random.nextInt(1 << 32)}';

    final pastaBase =
        await getApplicationDocumentsDirectory()
            .timeout(
      const Duration(
        seconds: 5,
      ),
    );

    final pasta =
        Directory(
      p.join(
        pastaBase.path,
        'canhotos',
        viagem.id,
        nota.chave,
      ),
    );

    // create(recursive:true) funciona tanto quando existe
    // quanto quando ainda não existe.
    await pasta
        .create(
      recursive: true,
    )
        .timeout(
      const Duration(
        seconds: 5,
      ),
    );

    var extensao =
        p.extension(
      imagemPath,
    ).toLowerCase();

    if (extensao != '.jpg' &&
        extensao != '.jpeg') {
      extensao = '.jpg';
    }

    final destino =
        p.join(
      pasta.path,
      '$id$extensao',
    );

    final arquivoSalvo =
        await origem
            .copy(
      destino,
    )
            .timeout(
      const Duration(
        seconds: 7,
      ),
    );

    final clienteMovimento =
        movimento.cliente
            ?.trim();

    final clienteViagem =
        viagem.cliente
            ?.trim();

    final cliente =
        clienteMovimento != null &&
                clienteMovimento.isNotEmpty
            ? clienteMovimento
            : clienteViagem;

    final canhoto =
        CanhotoLocal(
      id:
          id,
      viagemId:
          viagem.id,
      movimentoId:
          movimento.id,
      chaveNfe:
          nota.chave,
      numeroNfe:
          nota.numeroNfeFormatado,
      motorista:
          viagem.motorista,
      cliente:
          cliente,
      cidade:
          viagem.destino,
      tipoMovimento:
          movimento.tipoTexto,
      localPath:
          arquivoSalvo.path,
      storagePath:
          null,
      statusSync:
          'PENDENTE',
      capturadoEm:
          agora,
      tentativas:
          0,
      erroSync:
          null,
    );

    await DatabaseService.instance
        .salvarCanhotoLocal(
      canhoto,
    )
        .timeout(
      const Duration(
        seconds: 7,
      ),
    );

    // A foto temporária criada pelo plugin camera
    // não é mais necessária depois da cópia.
    try {
    if (removerArquivoOrigem && origem.path !=
              arquivoSalvo.path &&
          await origem.exists()) {
        await origem.delete();
      }
    } catch (_) {}

    return canhoto;
  }

  Future<List<CanhotoLocal>>
      buscarViagem(
    String viagemId,
  ) async {
    return DatabaseService.instance
        .buscarCanhotosViagem(
      viagemId,
    );
  }

  Future<List<CanhotoLocal>>
      buscarNota({
    required String viagemId,
    required String movimentoId,
    required String chaveNfe,
  }) async {
    return DatabaseService.instance
        .buscarCanhotosNota(
      viagemId:
          viagemId,
      movimentoId:
          movimentoId,
      chaveNfe:
          chaveNfe,
    );
  }

  Future<void> excluir(
    CanhotoLocal canhoto,
  ) async {
    await DatabaseService.instance
        .excluirCanhotoLocal(
      canhoto.id,
    );

    try {
      final arquivo =
          File(
        canhoto.localPath,
      );

      if (await arquivo.exists()) {
        await arquivo.delete();
      }
    } catch (_) {}
  }
}
