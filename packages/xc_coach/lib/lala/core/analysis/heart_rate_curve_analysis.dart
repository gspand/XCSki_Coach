import 'package:xc_coach/lala/core/models/test_stage.dart';
import 'package:xc_coach/lala/core/models/threshold_result.dart';
import 'package:xc_coach/lala/core/thresholds/curve_math.dart';
import 'package:xc_coach/lala/core/thresholds/hofmann_ltp_method.dart';

enum HeartRateCurveClassification { regular, linear, inverted }

class HeartRateCurveAnalysis {
  const HeartRateCurveAnalysis._({
    required this.reason,
    required this.sampleCount,
    this.ltp1Load,
    this.maximumLoad,
    this.khr,
    this.classification,
    this.hrtpLoad,
    this.hrtpHeartRate,
    this.hrtpReason,
    this.coefficients,
  });

  factory HeartRateCurveAnalysis.unavailable({
    required String reason,
    required int sampleCount,
    double? ltp1Load,
    double? maximumLoad,
  }) => HeartRateCurveAnalysis._(
    reason: reason,
    sampleCount: sampleCount,
    ltp1Load: ltp1Load,
    maximumLoad: maximumLoad,
  );

  final String reason;
  final int sampleCount;
  final double? ltp1Load;
  final double? maximumLoad;
  final double? khr;
  final HeartRateCurveClassification? classification;
  final double? hrtpLoad;
  final double? hrtpHeartRate;
  final String? hrtpReason;
  final List<double>? coefficients;

  bool get isAvailable => khr != null;
  bool get isHrtpDetermined => hrtpLoad != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'available': isAvailable,
    'reason': reason,
    'sampleCount': sampleCount,
    'ltp1Load': ltp1Load,
    'maximumLoad': maximumLoad,
    'kHR': khr,
    'classification': classification?.name,
    'hrtpLoad': hrtpLoad,
    'hrtpHeartRate': hrtpHeartRate,
    'hrtpReason': hrtpReason,
    'coefficients': coefficients,
    'formula':
        'normalized_HR = a + b*x + kHR*x^2; x = (load - LTP1) / (Pmax - LTP1)',
  };
}

class HeartRateCurveAnalysisService {
  const HeartRateCurveAnalysisService();

  HeartRateCurveAnalysis analyze({
    required List<TestStage> stages,
    required List<ThresholdResult> thresholdResults,
  }) {
    final ltp1 = thresholdResults
        .where((result) => result.methodId == hofmannLtp1MethodId)
        .firstOrNull;
    final ltp1Load = ltp1?.thresholdLoad;
    if (ltp1Load == null) {
      return HeartRateCurveAnalysis.unavailable(
        reason:
            'LTP1 ist nicht verfuegbar; der HR-Verlauf wird nicht unabhaengig davon substituiert.',
        sampleCount: 0,
      );
    }
    final valid = stages
        .where(
          (stage) =>
              stage.isValid &&
              stage.heartRate != null &&
              stage.load >= ltp1Load,
        )
        .toList(growable: false);
    if (valid.length < 3) {
      return HeartRateCurveAnalysis.unavailable(
        reason:
            'Mindestens drei reale HF-Stufen zwischen LTP1 und Pmax sind erforderlich.',
        sampleCount: valid.length,
        ltp1Load: ltp1Load,
        maximumLoad: stages
            .where((stage) => stage.isValid)
            .map((stage) => stage.load)
            .fold<double?>(
              null,
              (maximum, load) =>
                  maximum == null || load > maximum ? load : maximum,
            ),
      );
    }
    final pmax = valid.last.load;
    if (pmax <= ltp1Load) {
      return HeartRateCurveAnalysis.unavailable(
        reason: 'Pmax muss oberhalb von LTP1 liegen.',
        sampleCount: valid.length,
        ltp1Load: ltp1Load,
        maximumLoad: pmax,
      );
    }
    final heartRates = valid
        .map((stage) => stage.heartRate!.toDouble())
        .toList(growable: false);
    final minimumHeartRate = heartRates.reduce(
      (left, right) => left < right ? left : right,
    );
    final maximumHeartRate = heartRates.reduce(
      (left, right) => left > right ? left : right,
    );
    final heartRateRange = maximumHeartRate - minimumHeartRate;
    if (heartRateRange <= absoluteEpsilon) {
      return HeartRateCurveAnalysis.unavailable(
        reason:
            'Die HF zwischen LTP1 und Pmax variiert nicht ausreichend fuer eine Kurvenanalyse.',
        sampleCount: valid.length,
        ltp1Load: ltp1Load,
        maximumLoad: pmax,
      );
    }
    final normalizedLoad = valid
        .map((stage) => (stage.load - ltp1Load) / (pmax - ltp1Load))
        .toList(growable: false);
    final normalizedHeartRate = heartRates
        .map((heartRate) => (heartRate - minimumHeartRate) / heartRateRange)
        .toList(growable: false);
    final polynomial = QuadraticPolynomial.fit(
      normalizedLoad,
      normalizedHeartRate,
    );
    if (polynomial == null) {
      return HeartRateCurveAnalysis.unavailable(
        reason:
            'Die quadratische HR-Regression ist numerisch nicht bestimmbar.',
        sampleCount: valid.length,
        ltp1Load: ltp1Load,
        maximumLoad: pmax,
      );
    }
    final khr = polynomial.coefficients[2];
    final classification = khr > .1
        ? HeartRateCurveClassification.regular
        : khr < -.1
        ? HeartRateCurveClassification.inverted
        : HeartRateCurveClassification.linear;
    final vertex = -polynomial.coefficients[1] / (2 * khr);
    final hrtpEligible = khr.abs() >= .2;
    final hasInternalVertex = vertex.isFinite && vertex >= 0 && vertex <= 1;
    final hrtpLoad = hrtpEligible && hasInternalVertex
        ? ltp1Load + vertex * (pmax - ltp1Load)
        : null;
    final hrtpHeartRate = hrtpLoad == null
        ? null
        : (minimumHeartRate + polynomial(vertex) * heartRateRange);
    return HeartRateCurveAnalysis._(
      reason:
          'Quadratische HR-Regression aus realen Stufen zwischen LTP1 und Pmax.',
      sampleCount: valid.length,
      ltp1Load: ltp1Load,
      maximumLoad: pmax,
      khr: khr,
      classification: classification,
      hrtpLoad: hrtpLoad,
      hrtpHeartRate: hrtpHeartRate,
      hrtpReason: !hrtpEligible
          ? '|kHR| liegt unter 0.2; HRTP wird nicht bestimmt.'
          : !hasInternalVertex
          ? 'Der quadratische Vertex liegt ausserhalb von LTP1 bis Pmax; HRTP wird nicht bestimmt.'
          : 'HRTP aus dem Vertex der quadratischen Regression.',
      coefficients: polynomial.coefficients,
    );
  }
}
