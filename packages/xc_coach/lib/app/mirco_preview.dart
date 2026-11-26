/// English presentation for the Ercolina trial: --dart-define=MIRCO_PREVIEW=true.
/// Feature availability belongs to the product surface, never this language
/// flag. Ercolina includes training, Ercolina analysis, devices and training settings;
/// the separate Coach and Test areas are not part of that product.
library;

const bool mircoPreview = bool.fromEnvironment('MIRCO_PREVIEW');

String previewText(String german, String english) =>
    mircoPreview ? english : german;
