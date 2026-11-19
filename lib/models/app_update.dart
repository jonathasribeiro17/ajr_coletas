class AppUpdate {
  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String? observacao;

  const AppUpdate({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    this.observacao,
  });

  factory AppUpdate.fromMap(Map<String, dynamic> map) {
    return AppUpdate(
      versionCode: int.tryParse(map['version_code']?.toString() ?? '') ?? 0,
      versionName: map['version_name']?.toString().trim() ?? '',
      downloadUrl: map['download_url']?.toString().trim() ?? '',
      observacao: map['observacao']?.toString().trim(),
    );
  }

  bool get estaValida => versionCode > 0 && downloadUrl.isNotEmpty;
}
