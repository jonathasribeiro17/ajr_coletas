import 'package:flutter/material.dart';

import '../../data/destinos.dart';
import '../../models/cidade_empresa_cadastro.dart';
import '../../models/viagem.dart';
import '../../services/cadastro_destino_service.dart';
import '../../services/database_service.dart';
import 'viagem_screen.dart';

class NovaViagemScreen extends StatefulWidget {
  final String nomeMotorista;

  const NovaViagemScreen({
    super.key,
    required this.nomeMotorista,
  });

  @override
  State<NovaViagemScreen> createState() =>
      _NovaViagemScreenState();
}

class _NovaViagemScreenState
    extends State<NovaViagemScreen> {
  static const String _outraCidade =
      'Outra cidade';

  static const String _outraEmpresa =
      'Outra empresa';

  final TextEditingController
      _outraCidadeController =
      TextEditingController();

  final TextEditingController
      _outraEmpresaController =
      TextEditingController();

  final List<CidadeEmpresaCadastro>
      _catalogo = [];

  String? _destinoSelecionado;
  String? _empresaSelecionada;

  bool _salvando = false;
  bool _carregandoCadastros = true;

  late DateTime _dataViagem;

  @override
  void initState() {
    super.initState();

    final hoje = DateTime.now();

    _dataViagem = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    );

    _carregarCadastros();
  }

  @override
  void dispose() {
    _outraCidadeController.dispose();
    _outraEmpresaController.dispose();

    super.dispose();
  }

  // ============================================================
  // CIDADES / EMPRESAS
  // ============================================================

  Future<void> _carregarCadastros() async {
    try {
      final itens =
          await CadastroDestinoService.instance
              .carregarCatalogo();

      if (!mounted) {
        return;
      }

      setState(() {
        _catalogo
          ..clear()
          ..addAll(
            itens,
          );

        _carregandoCadastros = false;

        _ajustarEmpresaSelecionada();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      // Mesmo que o Supabase e o cache falhem,
      // as cidades fixas antigas continuam disponíveis.
      setState(() {
        _carregandoCadastros = false;
      });
    }
  }

  List<String> get _cidades {
    final porNormalizado =
        <String, String>{};

    // Mantém as cidades que o app já possuía antes da versão 2.
    for (final cidade in destinos) {
      if (cidade == _outraCidade) {
        continue;
      }

      final normalizada =
          DatabaseService
              .normalizarCadastroTexto(
        cidade,
      );

      porNormalizado.putIfAbsent(
        normalizada,
        () => cidade,
      );
    }

    // O catálogo vindo do Supabase pode acrescentar cidades novas.
    // Quando houver a mesma cidade no servidor, preferimos o nome
    // do catálogo remoto/cache.
    for (final item in _catalogo) {
      final cidade =
          item.cidadeNome.trim();

      if (cidade.isEmpty) {
        continue;
      }

      final normalizada =
          DatabaseService
              .normalizarCadastroTexto(
        cidade,
      );

      porNormalizado[normalizada] =
          cidade;
    }

    final lista =
        porNormalizado.values.toList()
          ..sort(
            (a, b) =>
                a.toLowerCase().compareTo(
              b.toLowerCase(),
            ),
          );

    lista.add(
      _outraCidade,
    );

    return lista;
  }

  List<String> get _empresasDaCidade {
    final cidade =
        _destinoSelecionado;

    if (cidade == null ||
        cidade == _outraCidade) {
      return [];
    }

    final cidadeNorm =
        DatabaseService
            .normalizarCadastroTexto(
      cidade,
    );

    final itens =
        _catalogo.where(
      (item) {
        return item.temEmpresa &&
            DatabaseService
                    .normalizarCadastroTexto(
                  item.cidadeNome,
                ) ==
                cidadeNorm;
      },
    ).toList();

    itens.sort(
      (a, b) {
        final uso =
            b.quantidadeUso.compareTo(
          a.quantidadeUso,
        );

        if (uso != 0) {
          return uso;
        }

        final aData =
            a.ultimoUsoEm;

        final bData =
            b.ultimoUsoEm;

        if (aData != null &&
            bData != null) {
          final data =
              bData.compareTo(
            aData,
          );

          if (data != 0) {
            return data;
          }
        }

        return a.empresaNome
            .toLowerCase()
            .compareTo(
              b.empresaNome
                  .toLowerCase(),
            );
      },
    );

    final nomes =
        <String>[];

    final usados =
        <String>{};

    for (final item in itens) {
      final normalizado =
          DatabaseService
              .normalizarCadastroTexto(
        item.empresaNome,
      );

      if (usados.add(
        normalizado,
      )) {
        nomes.add(
          item.empresaNome,
        );
      }
    }

    return nomes;
  }

  void _cidadeAlterada(
    String? valor,
  ) {
    setState(() {
      _destinoSelecionado =
          valor;

      _empresaSelecionada =
          null;

      _outraEmpresaController
          .clear();

      if (valor != _outraCidade) {
        _outraCidadeController
            .clear();
      }

      _ajustarEmpresaSelecionada();
    });
  }

  void _ajustarEmpresaSelecionada() {
    if (_destinoSelecionado == null) {
      return;
    }

    if (_destinoSelecionado ==
        _outraCidade) {
      _empresaSelecionada =
          _outraEmpresa;

      return;
    }

    final empresas =
        _empresasDaCidade;

    // Se aquela cidade só possui uma empresa,
    // o motorista nem precisa escolhê-la.
    if (empresas.length == 1) {
      _empresaSelecionada =
          empresas.first;
    }
  }

  String? _cidadeFinal() {
    if (_destinoSelecionado ==
        _outraCidade) {
      final valor =
          _outraCidadeController.text
              .trim();

      return valor.isEmpty
          ? null
          : valor;
    }

    return _destinoSelecionado;
  }

  String? _empresaFinal() {
    if (_empresaSelecionada ==
        _outraEmpresa) {
      final valor =
          _outraEmpresaController.text
              .trim();

      return valor.isEmpty
          ? null
          : valor;
    }

    final valor =
        _empresaSelecionada
            ?.trim();

    if (valor == null ||
        valor.isEmpty) {
      return null;
    }

    return valor;
  }

  // ============================================================
  // DATA
  // ============================================================

  String _formatarData(
    DateTime data,
  ) {
    final dia =
        data.day.toString().padLeft(
              2,
              '0',
            );

    final mes =
        data.month.toString().padLeft(
              2,
              '0',
            );

    return '$dia/$mes/${data.year}';
  }

  bool get _ehHoje {
    final hoje = DateTime.now();

    return hoje.year ==
            _dataViagem.year &&
        hoje.month ==
            _dataViagem.month &&
        hoje.day ==
            _dataViagem.day;
  }

  Future<void> _selecionarData() async {
    final hoje = DateTime.now();

    final data =
        await showDatePicker(
      context: context,
      initialDate:
          _dataViagem,
      firstDate: DateTime(
        hoje.year - 2,
      ),
      lastDate: DateTime(
        hoje.year,
        hoje.month,
        hoje.day,
      ),
      helpText:
          'DATA DA VIAGEM',
      cancelText:
          'CANCELAR',
      confirmText:
          'CONFIRMAR',
    );

    if (data == null) {
      return;
    }

    setState(() {
      _dataViagem =
          DateTime(
        data.year,
        data.month,
        data.day,
      );
    });
  }

  // ============================================================
  // INICIAR VIAGEM
  // ============================================================

  Future<void> _iniciarViagem() async {
    final cidade =
        _cidadeFinal();

    if (cidade == null) {
      _mensagem(
        _destinoSelecionado ==
                _outraCidade
            ? 'Digite a cidade de destino.'
            : 'Selecione a cidade de destino.',
      );

      return;
    }

    final empresa =
        _empresaFinal();

    if (empresa == null) {
      _mensagem(
        _empresaSelecionada ==
                _outraEmpresa
            ? 'Digite o nome da empresa.'
            : 'Selecione a empresa.',
      );

      return;
    }

    setState(() {
      _salvando = true;
    });

    final agora =
        DateTime.now();

    final dataInicio =
        DateTime(
      _dataViagem.year,
      _dataViagem.month,
      _dataViagem.day,
      agora.hour,
      agora.minute,
      agora.second,
    );

    final viagem =
        Viagem(
      id: agora
          .microsecondsSinceEpoch
          .toString(),
      motorista:
          widget.nomeMotorista,
      destino:
          cidade,
      cliente:
          empresa,
      dataInicio:
          dataInicio,
      dataFim:
          null,
      status:
          'ABERTA',
      movimentos:
          [],
    );

    try {
      // 1) Viagem continua sendo salva primeiro no SQLite,
      // exatamente como antes.
      await DatabaseService.instance
          .salvarViagem(
        viagem,
      );

      // 2) Cidade/empresa também é gravada localmente.
      // Se estiver sem internet, fica pendente e sincroniza depois.
      await CadastroDestinoService.instance
          .registrarUso(
        cidade: cidade,
        empresa: empresa,
      );

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  ViagemScreen(
            viagem: viagem,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _mensagem(
        'Erro ao iniciar viagem: $e',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _salvando =
              false;
        });
      }
    }
  }

  void _mensagem(
    String texto, {
    bool erro = false,
  }) {
    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(texto),
        backgroundColor:
            erro
                ? Colors.red
                : Colors.orange,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final theme =
        Theme.of(context);

    final empresas =
        _empresasDaCidade;

    final cidadeEscolhida =
        _destinoSelecionado != null;

    final cidadeManual =
        _destinoSelecionado ==
            _outraCidade;

    final precisaEmpresaManual =
        cidadeManual ||
            empresas.isEmpty ||
            _empresaSelecionada ==
                _outraEmpresa;

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF5F7FA,
      ),
      appBar:
          AppBar(
        title:
            const Text(
          'Nova Viagem',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip:
                'Atualizar cidades e empresas',
            onPressed:
                _carregandoCadastros
                    ? null
                    : () async {
                        setState(() {
                          _carregandoCadastros =
                              true;
                        });

                        await _carregarCadastros();
                      },
            icon:
                _carregandoCadastros
                    ? const SizedBox(
                        width:
                            18,
                        height:
                            18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth:
                              2,
                        ),
                      )
                    : const Icon(
                        Icons.refresh,
                      ),
          ),
        ],
      ),
      body:
          SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            20,
          ),
          child:
              Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      theme
                          .colorScheme
                          .primaryContainer,
                  borderRadius:
                      BorderRadius.circular(
                    14,
                  ),
                ),
                child:
                    Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          theme
                              .colorScheme
                              .primary,
                      foregroundColor:
                          Colors.white,
                      child:
                          const Icon(
                        Icons.person,
                      ),
                    ),
                    const SizedBox(
                      width:
                          12,
                    ),
                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'Motorista',
                            style:
                                TextStyle(
                              fontSize:
                                  12,
                            ),
                          ),
                          Text(
                            widget
                                .nomeMotorista,
                            style:
                                const TextStyle(
                              fontSize:
                                  17,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height:
                    24,
              ),

              const Text(
                'Data da viagem',
                style:
                    TextStyle(
                  fontSize:
                      20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height:
                    10,
              ),

              InkWell(
                onTap:
                    _selecionarData,
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                child:
                    Container(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.white,
                    borderRadius:
                        BorderRadius.circular(
                      14,
                    ),
                  ),
                  child:
                      Row(
                    children: [
                      const Icon(
                        Icons.calendar_month,
                        size:
                            32,
                      ),
                      const SizedBox(
                        width:
                            14,
                      ),
                      Expanded(
                        child:
                            Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              _formatarData(
                                _dataViagem,
                              ),
                              style:
                                  const TextStyle(
                                fontSize:
                                    19,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            Text(
                              _ehHoje
                                  ? 'Hoje'
                                  : 'Data alterada',
                              style:
                                  TextStyle(
                                color:
                                    _ehHoje
                                        ? Colors.green
                                        : Colors.orange,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.edit_calendar,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(
                height:
                    28,
              ),

              const Text(
                'Destino',
                style:
                    TextStyle(
                  fontSize:
                      20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              const SizedBox(
                height:
                    6,
              ),

              Text(
                'Escolha a cidade e depois a empresa.',
                style:
                    TextStyle(
                  color:
                      Colors.grey.shade600,
                ),
              ),

              const SizedBox(
                height:
                    14,
              ),

              DropdownButtonFormField<
                  String>(
                value:
                    _destinoSelecionado,
                isExpanded:
                    true,
                decoration:
                    InputDecoration(
                  labelText:
                      'Cidade',
                  prefixIcon:
                      const Icon(
                    Icons.location_city,
                  ),
                  filled:
                      true,
                  fillColor:
                      Colors.white,
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
                items:
                    _cidades.map(
                  (cidade) {
                    return DropdownMenuItem<
                        String>(
                      value:
                          cidade,
                      child:
                          Text(
                        cidade,
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                    );
                  },
                ).toList(),
                onChanged:
                    _salvando
                        ? null
                        : _cidadeAlterada,
              ),

              if (cidadeManual) ...[
                const SizedBox(
                  height:
                      14,
                ),
                TextField(
                  controller:
                      _outraCidadeController,
                  enabled:
                      !_salvando,
                  textCapitalization:
                      TextCapitalization.words,
                  decoration:
                      InputDecoration(
                    labelText:
                        'Nome da cidade',
                    hintText:
                        'Ex.: Araraquara - SP',
                    prefixIcon:
                        const Icon(
                      Icons.edit_location_alt,
                    ),
                    filled:
                        true,
                    fillColor:
                        Colors.white,
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                  ),
                ),
              ],

              if (cidadeEscolhida) ...[
                const SizedBox(
                  height:
                      18,
                ),

                if (!cidadeManual &&
                    empresas.isNotEmpty)
                  DropdownButtonFormField<
                      String>(
                    value:
                        _empresaSelecionada,
                    isExpanded:
                        true,
                    decoration:
                        InputDecoration(
                      labelText:
                          'Empresa',
                      prefixIcon:
                          const Icon(
                        Icons.business,
                      ),
                      filled:
                          true,
                      fillColor:
                          Colors.white,
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    items: [
                      ...empresas.map(
                        (empresa) =>
                            DropdownMenuItem<
                                String>(
                          value:
                              empresa,
                          child:
                              Text(
                            empresa,
                            overflow:
                                TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const DropdownMenuItem<
                          String>(
                        value:
                            _outraEmpresa,
                        child:
                            Text(
                          '+ Outra empresa',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    onChanged:
                        _salvando
                            ? null
                            : (valor) {
                                setState(() {
                                  _empresaSelecionada =
                                      valor;

                                  if (valor !=
                                      _outraEmpresa) {
                                    _outraEmpresaController
                                        .clear();
                                  }
                                });
                              },
                  ),

                if (!cidadeManual &&
                    empresas.isEmpty)
                  Container(
                    padding:
                        const EdgeInsets.all(
                      13,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.orange
                              .withValues(
                        alpha:
                            0.08,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    child:
                        const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color:
                              Colors.orange,
                        ),
                        SizedBox(
                          width:
                              9,
                        ),
                        Expanded(
                          child:
                              Text(
                            'Ainda não há empresa cadastrada para esta cidade.',
                          ),
                        ),
                      ],
                    ),
                  ),

                if (precisaEmpresaManual) ...[
                  if (!cidadeManual &&
                      empresas.isNotEmpty)
                    const SizedBox(
                      height:
                          14,
                    ),

                  if (!cidadeManual &&
                      empresas.isEmpty)
                    const SizedBox(
                      height:
                          14,
                    ),

                  TextField(
                    controller:
                        _outraEmpresaController,
                    enabled:
                        !_salvando,
                    textCapitalization:
                        TextCapitalization.words,
                    decoration:
                        InputDecoration(
                      labelText:
                          'Nome da empresa',
                      hintText:
                          'Ex.: Tenneco',
                      prefixIcon:
                          const Icon(
                        Icons.add_business,
                      ),
                      filled:
                          true,
                      fillColor:
                          Colors.white,
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    onChanged:
                        (_) {
                      if (_empresaSelecionada !=
                          _outraEmpresa) {
                        setState(() {
                          _empresaSelecionada =
                              _outraEmpresa;
                        });
                      }
                    },
                  ),
                ],
              ],

              if (_carregandoCadastros) ...[
                const SizedBox(
                  height:
                      12,
                ),
                const Row(
                  children: [
                    SizedBox(
                      width:
                          16,
                      height:
                          16,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2,
                      ),
                    ),
                    SizedBox(
                      width:
                          9,
                    ),
                    Text(
                      'Atualizando cidades e empresas...',
                    ),
                  ],
                ),
              ],

              const SizedBox(
                height:
                    35,
              ),

              SizedBox(
                height:
                    58,
                child:
                    FilledButton.icon(
                  onPressed:
                      _salvando
                          ? null
                          : _iniciarViagem,
                  icon:
                      _salvando
                          ? const SizedBox(
                              width:
                                  20,
                              height:
                                  20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : const Icon(
                              Icons.play_arrow,
                            ),
                  label:
                      Text(
                    _salvando
                        ? 'INICIANDO...'
                        : 'INICIAR VIAGEM',
                    style:
                        const TextStyle(
                      fontSize:
                          16,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
