import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/app_update.dart';

typedef AppUpdateProgress = void Function(int recebido, int? total);

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._();
  AppUpdateService._();

  static const String _manifestoUrl =
      'https://ajr-canhotos.jonathasribeiro17.workers.dev/app/latest.json';

  Future<AppUpdate?> buscarAtualizacaoDisponivel() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final versaoAtual = int.tryParse(packageInfo.buildNumber) ?? 0;

    final resposta = await http
        .get(Uri.parse(_manifestoUrl))
        .timeout(const Duration(seconds: 12));
    if (resposta.statusCode == 404) return null;
    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw Exception('Não foi possível consultar a atualização.');
    }

    final dados = jsonDecode(resposta.body);
    if (dados is! Map<String, dynamic>) {
      throw Exception('Resposta de atualização inválida.');
    }
    final atualizacao = AppUpdate.fromMap(dados);
    if (!atualizacao.estaValida || atualizacao.versionCode <= versaoAtual) {
      return null;
    }
    return atualizacao;
  }

  Future<void> baixarEInstalar(
    AppUpdate atualizacao, {
    AppUpdateProgress? onProgress,
  }) async {
    final uri = Uri.tryParse(atualizacao.downloadUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception('O link da atualização é inválido.');
    }

    final resposta = await http.Client().send(http.Request('GET', uri));
    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      throw Exception('Não foi possível baixar a atualização (${resposta.statusCode}).');
    }

    // O FileProvider do Android já autoriza a pasta de cache. Assim o APK
    // pode ser compartilhado com o instalador sem expor outros arquivos.
    final pastaBase = await getTemporaryDirectory();
    final pasta = Directory(path.join(pastaBase.path, 'atualizacoes'));
    await pasta.create(recursive: true);
    final arquivo = File(path.join(pasta.path, 'ajr_coletas_${atualizacao.versionCode}.apk'));
    final gravador = arquivo.openWrite();
    final total = resposta.contentLength;
    var recebido = 0;

    try {
      await for (final bytes in resposta.stream) {
        gravador.add(bytes);
        recebido += bytes.length;
        onProgress?.call(recebido, total);
      }
      await gravador.close();
    } catch (_) {
      await gravador.close();
      if (await arquivo.exists()) await arquivo.delete();
      rethrow;
    }

    OpenResult resultado;
    try {
      resultado = await OpenFilex.open(
        arquivo.path,
        type: 'application/vnd.android.package-archive',
      );
    } catch (_) {
      throw Exception(
        'Não foi possível abrir o instalador do Android. '
        'Confira a permissão para instalar aplicativos.',
      );
    }
    if (resultado.type != ResultType.done) {
      throw Exception(
        'Não foi possível abrir o instalador. ${resultado.message}',
      );
    }
  }
}
