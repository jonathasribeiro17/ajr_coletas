# ============================================================
# AJR COLETAS
# GOOGLE ML KIT TEXT RECOGNITION
# ============================================================

# O AJR utiliza somente o reconhecimento LATIN.
#
# O plugin google_mlkit_text_recognition possui referências
# opcionais para outros alfabetos.
#
# Como esses módulos não estão instalados, o R8 encontra
# referências às classes e interrompe o build release.
#
# Essas regras dizem ao R8 que essas ausências são esperadas.


# ============================================================
# CHINESE
# ============================================================

-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder


# ============================================================
# DEVANAGARI
# ============================================================

-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder


# ============================================================
# JAPANESE
# ============================================================

-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder


# ============================================================
# KOREAN
# ============================================================

-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder