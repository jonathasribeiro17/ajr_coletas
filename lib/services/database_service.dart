import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/canhoto_local.dart';
import '../models/movimento.dart';
import '../models/nota_fiscal.dart';
import '../models/viagem.dart';

class DatabaseService {
  static final DatabaseService instance =
      DatabaseService._();

  static Database? _database;

  DatabaseService._();

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath =
        await getDatabasesPath();

    final path = join(
      databasePath,
      'ajr_coletas.db',
    );

    return openDatabase(
      path,
      version: 7,
      onConfigure: (db) async {
        await db.execute(
          'PRAGMA foreign_keys = ON',
        );
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(
    Database db,
    int version,
  ) async {
    await _criarTabelas(db);
  }

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'DROP TABLE IF EXISTS notas_fiscais',
      );

      await db.execute(
        'DROP TABLE IF EXISTS coletas',
      );

      await db.execute(
        'DROP TABLE IF EXISTS movimentos',
      );

      await db.execute(
        'DROP TABLE IF EXISTS viagens',
      );

      await _criarTabelas(db);

      return;
    }

    if (oldVersion < 3) {
      await db.execute('''
        ALTER TABLE viagens
        ADD COLUMN sincronizada INTEGER NOT NULL DEFAULT 0
      ''');
    }

    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE movimentos
        ADD COLUMN cliente TEXT
      ''');
    }

    if (oldVersion < 5) {
      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN destinatario_nome TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN destinatario_cnpj TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN destinatario_endereco TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN destinatario_municipio TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN destinatario_uf TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN recebedor_cnpj TEXT
      ''');

      await db.execute('''
        ALTER TABLE notas_fiscais
        ADD COLUMN endereco_entrega TEXT
      ''');
    }

    if (oldVersion < 6) {
      await _criarTabelaCacheCidadeEmpresa(
        db,
      );
    }

    if (oldVersion < 7) {
      await _criarTabelaCanhotos(
        db,
      );
    }
  }

  Future<void> _criarTabelas(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE viagens (
        id TEXT PRIMARY KEY,
        motorista TEXT NOT NULL,
        destino TEXT NOT NULL,
        cliente TEXT,
        data_inicio TEXT NOT NULL,
        data_fim TEXT,
        status TEXT NOT NULL,
        sincronizada INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE movimentos (
        id TEXT PRIMARY KEY,
        viagem_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        cliente TEXT,
        data_hora TEXT NOT NULL,
        FOREIGN KEY (viagem_id)
          REFERENCES viagens (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE notas_fiscais (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        movimento_id TEXT NOT NULL,
        chave TEXT NOT NULL,
        data_leitura TEXT NOT NULL,
        destinatario_nome TEXT,
        destinatario_cnpj TEXT,
        destinatario_endereco TEXT,
        destinatario_municipio TEXT,
        destinatario_uf TEXT,
        recebedor_cnpj TEXT,
        endereco_entrega TEXT,
        FOREIGN KEY (movimento_id)
          REFERENCES movimentos (id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_nota_movimento_chave
      ON notas_fiscais (
        movimento_id,
        chave
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_movimento_viagem
      ON movimentos (viagem_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_viagem_sincronizada
      ON viagens (sincronizada)
    ''');

    await _criarTabelaCacheCidadeEmpresa(
      db,
    );

    await _criarTabelaCanhotos(
      db,
    );
  }

  Future<void> _criarTabelaCanhotos(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS canhotos_locais (
        id TEXT PRIMARY KEY,

        viagem_id TEXT NOT NULL,
        movimento_id TEXT NOT NULL,

        chave_nfe TEXT NOT NULL,
        numero_nfe TEXT NOT NULL,

        motorista TEXT NOT NULL,
        cliente TEXT,
        cidade TEXT NOT NULL,
        tipo_movimento TEXT NOT NULL,

        local_path TEXT NOT NULL,
        storage_path TEXT,

        status_sync TEXT NOT NULL DEFAULT 'PENDENTE',
        capturado_em TEXT NOT NULL,

        tentativas INTEGER NOT NULL DEFAULT 0,
        erro_sync TEXT,

        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_canhotos_viagem
      ON canhotos_locais (
        viagem_id
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_canhotos_nfe
      ON canhotos_locais (
        chave_nfe
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_canhotos_movimento_nfe
      ON canhotos_locais (
        viagem_id,
        movimento_id,
        chave_nfe
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_canhotos_sync
      ON canhotos_locais (
        status_sync
      )
    ''');
  }

  // ============================================================
  // CANHOTOS LOCAIS
  // ============================================================

  Future<void> salvarCanhotoLocal(
    CanhotoLocal canhoto,
  ) async {
    final db = await database;

    await db.insert(
      'canhotos_locais',
      canhoto.toDbMap(),
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<List<CanhotoLocal>>
      buscarCanhotosViagem(
    String viagemId,
  ) async {
    final db = await database;

    final resultado =
        await db.query(
      'canhotos_locais',
      where:
          'viagem_id = ?',
      whereArgs: [
        viagemId,
      ],
      orderBy:
          'capturado_em ASC',
    );

    return resultado
        .map(
          (item) =>
              CanhotoLocal.fromDbMap(
            item,
          ),
        )
        .toList();
  }

  Future<List<CanhotoLocal>>
      buscarCanhotosNota({
    required String viagemId,
    required String movimentoId,
    required String chaveNfe,
  }) async {
    final db = await database;

    final resultado =
        await db.query(
      'canhotos_locais',
      where: '''
        viagem_id = ?
        AND movimento_id = ?
        AND chave_nfe = ?
      ''',
      whereArgs: [
        viagemId,
        movimentoId,
        chaveNfe,
      ],
      orderBy:
          'capturado_em ASC',
    );

    return resultado
        .map(
          (item) =>
              CanhotoLocal.fromDbMap(
            item,
          ),
        )
        .toList();
  }

  Future<List<CanhotoLocal>>
      buscarCanhotosPendentes() async {
    final db = await database;

    final resultado =
        await db.query(
      'canhotos_locais',
      where:
          'status_sync != ?',
      whereArgs: [
        'ENVIADO',
      ],
      orderBy:
          'capturado_em ASC',
    );

    return resultado
        .map(
          (item) =>
              CanhotoLocal.fromDbMap(
            item,
          ),
        )
        .toList();
  }

  Future<List<CanhotoLocal>>
      buscarCanhotosPendentesViagem(
    String viagemId,
  ) async {
    final db = await database;

    final resultado = await db.query(
      'canhotos_locais',
      where: '''
        viagem_id = ?
        AND status_sync != ?
      ''',
      whereArgs: [
        viagemId,
        'ENVIADO',
      ],
      orderBy: 'capturado_em ASC',
    );

    return resultado
        .map(
          (item) =>
              CanhotoLocal.fromDbMap(item),
        )
        .toList();
  }

  Future<void> excluirCanhotoLocal(
    String canhotoId,
  ) async {
    final db = await database;

    await db.delete(
      'canhotos_locais',
      where:
          'id = ?',
      whereArgs: [
        canhotoId,
      ],
    );
  }

  Future<void> marcarCanhotoEnviando(
    String canhotoId,
  ) async {
    final db = await database;

    await db.rawUpdate(
      '''
      UPDATE canhotos_locais
      SET
        status_sync = 'ENVIANDO',
        tentativas = tentativas + 1,
        erro_sync = NULL,
        updated_at = ?
      WHERE id = ?
      ''',
      [
        DateTime.now()
            .toIso8601String(),
        canhotoId,
      ],
    );
  }

  Future<void> marcarCanhotoEnviado({
    required String canhotoId,
    required String storagePath,
  }) async {
    final db = await database;

    await db.update(
      'canhotos_locais',
      {
        'status_sync':
            'ENVIADO',
        'storage_path':
            storagePath,
        'erro_sync':
            null,
        'updated_at':
            DateTime.now()
                .toIso8601String(),
      },
      where:
          'id = ?',
      whereArgs: [
        canhotoId,
      ],
    );
  }

  Future<void> marcarCanhotoErro({
    required String canhotoId,
    required String erro,
  }) async {
    final db = await database;

    await db.update(
      'canhotos_locais',
      {
        'status_sync':
            'ERRO',
        'erro_sync':
            erro,
        'updated_at':
            DateTime.now()
                .toIso8601String(),
      },
      where:
          'id = ?',
      whereArgs: [
        canhotoId,
      ],
    );
  }

  Future<int> contarNotasComCanhoto(
    String viagemId,
  ) async {
    final db = await database;

    final resultado =
        await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM (
        SELECT DISTINCT
          movimento_id,
          chave_nfe
        FROM canhotos_locais
        WHERE viagem_id = ?
      )
      ''',
      [
        viagemId,
      ],
    );

    if (resultado.isEmpty) {
      return 0;
    }

    return _intValor(
      resultado.first['total'],
    );
  }

  Future<void> _criarTabelaCacheCidadeEmpresa(
    Database db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cidade_empresas_cache (
        cidade_id TEXT,
        cidade_nome TEXT NOT NULL,
        cidade_normalizada TEXT NOT NULL,

        empresa_id TEXT,
        empresa_nome TEXT NOT NULL DEFAULT '',
        empresa_normalizada TEXT NOT NULL DEFAULT '',

        quantidade_uso INTEGER NOT NULL DEFAULT 0,
        ultimo_uso_em TEXT,

        pendente_sync INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,

        PRIMARY KEY (
          cidade_normalizada,
          empresa_normalizada
        )
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cache_cidade_empresa
      ON cidade_empresas_cache (
        cidade_normalizada,
        quantidade_uso DESC
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cache_cadastro_pendente
      ON cidade_empresas_cache (
        pendente_sync
      )
    ''');
  }

  // ============================================================
  // CACHE CIDADE / EMPRESA
  // ============================================================

  Future<void> substituirCacheCidadeEmpresas(
    List<Map<String, dynamic>> registros,
  ) async {
    final db = await database;

    await db.transaction(
      (txn) async {
        // Apaga somente o que veio de sincronizações anteriores.
        // Cadastros novos feitos offline continuam preservados.
        await txn.delete(
          'cidade_empresas_cache',
          where: 'pendente_sync = ?',
          whereArgs: [
            0,
          ],
        );

        for (final item in registros) {
          final cidade =
              item['cidade_nome']
                      ?.toString()
                      .trim() ??
                  '';

          if (cidade.isEmpty) {
            continue;
          }

          final empresa =
              item['empresa_nome']
                      ?.toString()
                      .trim() ??
                  '';

          final quantidade =
              _intValor(
            item['quantidade_uso'],
          );

          final ultimoUso =
              item['ultimo_uso_em']
                  ?.toString();

          await txn.insert(
            'cidade_empresas_cache',
            {
              'cidade_id':
                  item['cidade_id']
                      ?.toString(),
              'cidade_nome':
                  cidade,
              'cidade_normalizada':
                  normalizarCadastroTexto(
                cidade,
              ),
              'empresa_id':
                  item['empresa_id']
                      ?.toString(),
              'empresa_nome':
                  empresa,
              'empresa_normalizada':
                  normalizarCadastroTexto(
                empresa,
              ),
              'quantidade_uso':
                  quantidade,
              'ultimo_uso_em':
                  ultimoUso,
              'pendente_sync':
                  0,
              'updated_at':
                  DateTime.now()
                      .toIso8601String(),
            },
            conflictAlgorithm:
                ConflictAlgorithm.replace,
          );
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>>
      buscarCacheCidadeEmpresas() async {
    final db = await database;

    final resultado =
        await db.query(
      'cidade_empresas_cache',
      orderBy: '''
        cidade_nome COLLATE NOCASE ASC,
        quantidade_uso DESC,
        ultimo_uso_em DESC,
        empresa_nome COLLATE NOCASE ASC
      ''',
    );

    return resultado
        .map(
          (item) =>
              Map<String, dynamic>.from(
            item,
          ),
        )
        .toList();
  }

  Future<void> salvarCadastroDestinoLocal({
    required String cidade,
    required String empresa,
    required bool pendenteSync,
  }) async {
    final db = await database;

    final cidadeFinal =
        cidade.trim();

    final empresaFinal =
        empresa.trim();

    if (cidadeFinal.isEmpty ||
        empresaFinal.isEmpty) {
      return;
    }

    final cidadeNorm =
        normalizarCadastroTexto(
      cidadeFinal,
    );

    final empresaNorm =
        normalizarCadastroTexto(
      empresaFinal,
    );

    final existente =
        await db.query(
      'cidade_empresas_cache',
      where: '''
        cidade_normalizada = ?
        AND empresa_normalizada = ?
      ''',
      whereArgs: [
        cidadeNorm,
        empresaNorm,
      ],
      limit: 1,
    );

    if (existente.isEmpty) {
      await db.insert(
        'cidade_empresas_cache',
        {
          'cidade_id':
              null,
          'cidade_nome':
              cidadeFinal,
          'cidade_normalizada':
              cidadeNorm,
          'empresa_id':
              null,
          'empresa_nome':
              empresaFinal,
          'empresa_normalizada':
              empresaNorm,
          'quantidade_uso':
              1,
          'ultimo_uso_em':
              DateTime.now()
                  .toIso8601String(),
          'pendente_sync':
              pendenteSync ? 1 : 0,
          'updated_at':
              DateTime.now()
                  .toIso8601String(),
        },
        conflictAlgorithm:
            ConflictAlgorithm.replace,
      );

      return;
    }

    final atual =
        existente.first;

    final quantidadeAtual =
        _intValor(
      atual['quantidade_uso'],
    );

    final jaPendente =
        _intValor(
              atual['pendente_sync'],
            ) ==
            1;

    await db.update(
      'cidade_empresas_cache',
      {
        'cidade_nome':
            cidadeFinal,
        'empresa_nome':
            empresaFinal,
        'quantidade_uso':
            quantidadeAtual + 1,
        'ultimo_uso_em':
            DateTime.now()
                .toIso8601String(),
        'pendente_sync':
            pendenteSync || jaPendente
                ? 1
                : 0,
        'updated_at':
            DateTime.now()
                .toIso8601String(),
      },
      where: '''
        cidade_normalizada = ?
        AND empresa_normalizada = ?
      ''',
      whereArgs: [
        cidadeNorm,
        empresaNorm,
      ],
    );
  }

  Future<List<Map<String, dynamic>>>
      buscarCadastrosDestinoPendentes() async {
    final db = await database;

    final resultado =
        await db.query(
      'cidade_empresas_cache',
      where:
          'pendente_sync = ?',
      whereArgs: [
        1,
      ],
      orderBy:
          'updated_at ASC',
    );

    return resultado
        .map(
          (item) =>
              Map<String, dynamic>.from(
            item,
          ),
        )
        .toList();
  }

  Future<void>
      marcarCadastroDestinoSincronizado({
    required String cidade,
    required String empresa,
    String? cidadeId,
    String? cidadeNome,
    String? empresaId,
    String? empresaNome,
  }) async {
    final db = await database;

    final cidadeNorm =
        normalizarCadastroTexto(
      cidade,
    );

    final empresaNorm =
        normalizarCadastroTexto(
      empresa,
    );

    await db.update(
      'cidade_empresas_cache',
      {
        'cidade_id':
            _textoOuNull(
                  cidadeId,
                ),
        'cidade_nome':
            _textoOuNull(
                  cidadeNome,
                ) ??
                cidade.trim(),
        'empresa_id':
            _textoOuNull(
                  empresaId,
                ),
        'empresa_nome':
            _textoOuNull(
                  empresaNome,
                ) ??
                empresa.trim(),
        'pendente_sync':
            0,
        'updated_at':
            DateTime.now()
                .toIso8601String(),
      },
      where: '''
        cidade_normalizada = ?
        AND empresa_normalizada = ?
      ''',
      whereArgs: [
        cidadeNorm,
        empresaNorm,
      ],
    );
  }

  static String normalizarCadastroTexto(
    String texto,
  ) {
    var valor =
        texto.trim().toUpperCase();

    const trocas = {
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ç': 'C',
      'Ñ': 'N',
    };

    for (final item
        in trocas.entries) {
      valor =
          valor.replaceAll(
        item.key,
        item.value,
      );
    }

    valor =
        valor.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    // Para o cadastro operacional,
    // "Mogi Mirim" e "Mogi Mirim - SP"
    // devem representar a mesma cidade.
    valor =
        valor.replaceFirst(
      RegExp(r'\s*-\s*SP$'),
      '',
    );

    return valor.trim();
  }

  static int _intValor(
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

  Future<void> salvarViagem(
    Viagem viagem,
  ) async {
    final db = await database;

    await db.insert(
      'viagens',
      {
        'id': viagem.id,
        'motorista': viagem.motorista,
        'destino': viagem.destino,
        'cliente': viagem.cliente,
        'data_inicio':
            viagem.dataInicio.toIso8601String(),
        'data_fim':
            viagem.dataFim?.toIso8601String(),
        'status': viagem.status,
        'sincronizada': 0,
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<void> salvarMovimento(
    Movimento movimento,
  ) async {
    final db = await database;

    await db.transaction(
      (txn) async {
        await txn.insert(
          'movimentos',
          {
            'id':
                movimento.id,
            'viagem_id':
                movimento.viagemId,
            'tipo':
                movimento.tipoTexto,
            'cliente':
                movimento.cliente,
            'data_hora':
                movimento.dataHora
                    .toIso8601String(),
          },
          conflictAlgorithm:
              ConflictAlgorithm.replace,
        );

        for (final nota in movimento.notas) {
          await txn.insert(
            'notas_fiscais',
            _mapNota(
              movimento.id,
              nota,
            ),
            conflictAlgorithm:
                ConflictAlgorithm.ignore,
          );
        }

        await txn.update(
          'viagens',
          {
            'sincronizada': 0,
          },
          where:
              'id = ?',
          whereArgs: [
            movimento.viagemId,
          ],
        );
      },
    );
  }

  Future<void> atualizarMovimento(
    Movimento movimento,
  ) async {
    final db = await database;

    await db.transaction(
      (txn) async {
        final atualizado =
            await txn.update(
          'movimentos',
          {
            'viagem_id':
                movimento.viagemId,
            'tipo':
                movimento.tipoTexto,
            'cliente':
                movimento.cliente,
            'data_hora':
                movimento.dataHora
                    .toIso8601String(),
          },
          where:
              'id = ?',
          whereArgs: [
            movimento.id,
          ],
        );

        if (atualizado == 0) {
          await txn.insert(
            'movimentos',
            {
              'id':
                  movimento.id,
              'viagem_id':
                  movimento.viagemId,
              'tipo':
                  movimento.tipoTexto,
              'cliente':
                  movimento.cliente,
              'data_hora':
                  movimento.dataHora
                      .toIso8601String(),
            },
            conflictAlgorithm:
                ConflictAlgorithm.replace,
          );
        }

        await txn.delete(
          'notas_fiscais',
          where:
              'movimento_id = ?',
          whereArgs: [
            movimento.id,
          ],
        );

        for (final nota in movimento.notas) {
          await txn.insert(
            'notas_fiscais',
            _mapNota(
              movimento.id,
              nota,
            ),
            conflictAlgorithm:
                ConflictAlgorithm.ignore,
          );
        }

        await txn.update(
          'viagens',
          {
            'sincronizada': 0,
          },
          where:
              'id = ?',
          whereArgs: [
            movimento.viagemId,
          ],
        );
      },
    );
  }

  Map<String, Object?> _mapNota(
    String movimentoId,
    NotaFiscal nota,
  ) {
    return {
      'movimento_id': movimentoId,
      'chave': nota.chave,
      'data_leitura':
          nota.dataLeitura.toIso8601String(),
      'destinatario_nome':
          nota.destinatarioNome,
      'destinatario_cnpj':
          nota.destinatarioCnpj,
      'destinatario_endereco':
          nota.destinatarioEndereco,
      'destinatario_municipio':
          nota.destinatarioMunicipio,
      'destinatario_uf':
          nota.destinatarioUf,
      'recebedor_cnpj':
          nota.recebedorCnpj,
      'endereco_entrega':
          nota.enderecoEntrega,
    };
  }

  Future<void> excluirMovimento({
    required String movimentoId,
    required String viagemId,
  }) async {
    final db = await database;

    await db.transaction(
      (txn) async {
        await txn.delete(
          'movimentos',
          where:
              'id = ? AND viagem_id = ?',
          whereArgs: [
            movimentoId,
            viagemId,
          ],
        );

        await txn.update(
          'viagens',
          {
            'sincronizada': 0,
          },
          where:
              'id = ?',
          whereArgs: [
            viagemId,
          ],
        );
      },
    );
  }

  Future<void> finalizarViagem(
    String viagemId,
  ) async {
    final db = await database;

    await db.update(
      'viagens',
      {
        'status': 'FINALIZADA',
        'data_fim':
            DateTime.now().toIso8601String(),
        'sincronizada': 0,
      },
      where:
          'id = ?',
      whereArgs: [
        viagemId,
      ],
    );
  }

  Future<void> cancelarViagem(
    String viagemId,
  ) async {
    final db = await database;

    await db.update(
      'viagens',
      {
        'status': 'CANCELADA',
        'data_fim':
            DateTime.now().toIso8601String(),
        'sincronizada': 0,
      },
      where:
          'id = ?',
      whereArgs: [
        viagemId,
      ],
    );
  }

  Future<void>
      marcarViagemPendenteSincronizacao(
    String viagemId,
  ) async {
    final db = await database;

    await db.update(
      'viagens',
      {
        'sincronizada': 0,
      },
      where:
          'id = ?',
      whereArgs: [
        viagemId,
      ],
    );
  }

  Future<void> marcarViagemSincronizada(
    String viagemId,
  ) async {
    final db = await database;

    await db.update(
      'viagens',
      {
        'sincronizada': 1,
      },
      where:
          'id = ?',
      whereArgs: [
        viagemId,
      ],
    );
  }

  Future<List<Viagem>>
      buscarViagensPendentesSincronizacao() async {
    final db = await database;

    final resultado =
        await db.query(
      'viagens',
      where:
          'sincronizada = ?',
      whereArgs: [
        0,
      ],
      orderBy:
          'data_inicio ASC',
    );

    final List<Viagem> viagens = [];

    for (final item in resultado) {
      viagens.add(
        await _montarViagem(
          db,
          item,
        ),
      );
    }

    return viagens;
  }

  Future<Viagem?> buscarViagemPorId(
    String viagemId,
  ) async {
    final db = await database;

    final resultado =
        await db.query(
      'viagens',
      where:
          'id = ?',
      whereArgs: [
        viagemId,
      ],
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return _montarViagem(
      db,
      resultado.first,
    );
  }

  Future<Viagem?> buscarViagemAberta(
    String motorista,
  ) async {
    final db = await database;

    final resultado =
        await db.query(
      'viagens',
      where:
          'motorista = ? AND status = ?',
      whereArgs: [
        motorista,
        'ABERTA',
      ],
      orderBy:
          'data_inicio DESC',
      limit: 1,
    );

    if (resultado.isEmpty) {
      return null;
    }

    return _montarViagem(
      db,
      resultado.first,
    );
  }

  Future<List<Viagem>> buscarViagens() async {
    final db = await database;

    final resultado =
        await db.query(
      'viagens',
      orderBy:
          'data_inicio DESC',
    );

    final List<Viagem> viagens = [];

    for (final item in resultado) {
      viagens.add(
        await _montarViagem(
          db,
          item,
        ),
      );
    }

    return viagens;
  }

  Future<List<Viagem>>
      buscarViagensMotorista(
    String motorista,
  ) async {
    final db = await database;

    final resultado =
        await db.query(
      'viagens',
      where:
          'motorista = ?',
      whereArgs: [
        motorista,
      ],
      orderBy:
          'data_inicio DESC',
    );

    final List<Viagem> viagens = [];

    for (final item in resultado) {
      viagens.add(
        await _montarViagem(
          db,
          item,
        ),
      );
    }

    return viagens;
  }

  Future<Viagem> _montarViagem(
    Database db,
    Map<String, Object?> viagemMap,
  ) async {
    final viagemId =
        viagemMap['id'] as String;

    final movimentosMap =
        await db.query(
      'movimentos',
      where:
          'viagem_id = ?',
      whereArgs: [
        viagemId,
      ],
      orderBy:
          'data_hora ASC',
    );

    final List<Movimento> movimentos = [];

    for (final movimentoMap
        in movimentosMap) {
      final movimentoId =
          movimentoMap['id'] as String;

      final notasMap =
          await db.query(
        'notas_fiscais',
        where:
            'movimento_id = ?',
        whereArgs: [
          movimentoId,
        ],
        orderBy:
            'id ASC',
      );

      final notas =
          notasMap.map(
        (notaMap) {
          return NotaFiscal(
            chave:
                notaMap['chave'] as String,
            dataLeitura:
                DateTime.parse(
              notaMap['data_leitura']
                  as String,
            ),
            destinatarioNome:
                notaMap[
                        'destinatario_nome']
                    as String?,
            destinatarioCnpj:
                notaMap[
                        'destinatario_cnpj']
                    as String?,
            destinatarioEndereco:
                notaMap[
                        'destinatario_endereco']
                    as String?,
            destinatarioMunicipio:
                notaMap[
                        'destinatario_municipio']
                    as String?,
            destinatarioUf:
                notaMap[
                        'destinatario_uf']
                    as String?,
            recebedorCnpj:
                notaMap[
                        'recebedor_cnpj']
                    as String?,
            enderecoEntrega:
                notaMap[
                        'endereco_entrega']
                    as String?,
          );
        },
      ).toList();

      movimentos.add(
        Movimento.fromMap(
          {
            'id':
                movimentoMap['id'],
            'viagemId':
                movimentoMap['viagem_id'],
            'tipo':
                movimentoMap['tipo'],
            'cliente':
                movimentoMap['cliente'],
            'dataHora':
                movimentoMap['data_hora'],
            'notas':
                notas
                    .map(
                      (nota) =>
                          nota.toMap(),
                    )
                    .toList(),
          },
        ),
      );
    }

    return Viagem(
      id:
          viagemId,
      motorista:
          viagemMap['motorista']
              as String,
      destino:
          viagemMap['destino']
              as String,
      cliente:
          viagemMap['cliente']
              as String?,
      dataInicio:
          DateTime.parse(
        viagemMap['data_inicio']
            as String,
      ),
      dataFim:
          viagemMap['data_fim'] != null
              ? DateTime.parse(
                  viagemMap['data_fim']
                      as String,
                )
              : null,
      status:
          viagemMap['status']
              as String,
      sincronizada:
          (viagemMap['sincronizada']
                      as int? ??
                  0) ==
              1,
      movimentos:
          movimentos,
    );
  }
}