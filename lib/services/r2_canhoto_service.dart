import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../models/canhoto_local.dart';

class R2CanhotoUploadResultado {
  final String storagePath;
  final String? comprovanteId;
  final String? fotoId;
  final bool jaExistia;

  const R2CanhotoUploadResultado({
    required this.storagePath,
    required this.comprovanteId,
    required this.fotoId,
    required this.jaExistia,
  });
}

class R2CanhotoService {
  static final R2CanhotoService instance =
      R2CanhotoService._();

  R2CanhotoService._();

  static const String _workerBaseUrl =
      'https://ajr-canhotos.jonathasribeiro17.workers.dev';

  Future<R2CanhotoUploadResultado> enviar(
    CanhotoLocal canhoto,
  ) async {
    final arquivo = File(canhoto.localPath);

    if (!await arquivo.exists()) {
      throw const CanhotoUploadException(
        'A foto não existe mais no celular.',
        code: 'ARQUIVO_LOCAL_NAO_ENCONTRADO',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_workerBaseUrl/upload'),
    );

    request.fields.addAll({
      'local_id': canhoto.id,
      'viagem_id': canhoto.viagemId,
      'movimento_id': canhoto.movimentoId,
      'chave_nfe': canhoto.chaveNfe,
      'numero_nfe': canhoto.numeroNfe,
      'motorista': canhoto.motorista,
      'cidade': canhoto.cidade,
      'tipo_movimento': canhoto.tipoMovimento,
      'capturado_em':
          canhoto.capturadoEm.toUtc().toIso8601String(),
    });

    final cliente = canhoto.cliente?.trim();
    if (cliente != null && cliente.isNotEmpty) {
      request.fields['cliente'] = cliente;
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'foto',
        canhoto.localPath,
        filename: p.basename(canhoto.localPath),
        contentType: _mimeType(canhoto.localPath),
      ),
    );

    http.StreamedResponse resposta;

    try {
      resposta = await request
          .send()
          .timeout(const Duration(seconds: 25));
    } on SocketException {
      throw const CanhotoUploadException(
        'Sem conexão com a internet.',
        code: 'SEM_INTERNET',
      );
    }

    final texto = await resposta.stream.bytesToString();

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(texto);
      if (decoded is Map) {
        body = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}

    if (resposta.statusCode < 200 ||
        resposta.statusCode >= 300 ||
        body?['ok'] != true) {
      final erro = body?['error']?.toString().trim();
      throw CanhotoUploadException(
        erro != null && erro.isNotEmpty
            ? erro
            : 'Falha no envio do canhoto '
                '(HTTP ${resposta.statusCode}).',
        code: body?['code']?.toString(),
        httpStatus: resposta.statusCode,
      );
    }

    final storagePath =
        body?['storage_path']?.toString().trim() ?? '';

    if (storagePath.isEmpty) {
      throw const CanhotoUploadException(
        'O servidor não retornou o caminho da foto.',
        code: 'STORAGE_PATH_AUSENTE',
      );
    }

    return R2CanhotoUploadResultado(
      storagePath: storagePath,
      comprovanteId:
          _textoOuNull(body?['comprovante_id']),
      fotoId: _textoOuNull(body?['foto_id']),
      jaExistia: body?['ja_existia'] == true,
    );
  }

  MediaType _mimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return MediaType('image', 'png');
      case '.webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  String? _textoOuNull(dynamic valor) {
    final texto = valor?.toString().trim();
    if (texto == null || texto.isEmpty) {
      return null;
    }
    return texto;
  }
}

class CanhotoUploadException implements Exception {
  final String message;
  final String? code;
  final int? httpStatus;

  const CanhotoUploadException(
    this.message, {
    this.code,
    this.httpStatus,
  });

  @override
  String toString() => message;
}
