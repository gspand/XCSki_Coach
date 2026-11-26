import 'dart:math' as math;

const double absoluteEpsilon = 1e-10;
const double relativeEpsilon = 1e-8;

bool approximatelyEqual(double first, double second) =>
    (first - second).abs() <= absoluteEpsilon ||
    (first - second).abs() <=
        relativeEpsilon * math.max(first.abs(), second.abs());

double _hypotenuse(double first, double second) {
  final larger = math.max(first.abs(), second.abs());
  if (larger == 0) {
    return 0;
  }
  final smaller = math.min(first.abs(), second.abs());
  final ratio = smaller / larger;
  return larger * math.sqrt(1 + ratio * ratio);
}

class CubicPolynomial {
  const CubicPolynomial(this.coefficients);

  final List<double> coefficients;

  double call(double value) =>
      coefficients[0] +
      coefficients[1] * value +
      coefficients[2] * value * value +
      coefficients[3] * value * value * value;

  double derivative(double value) =>
      coefficients[1] +
      2 * coefficients[2] * value +
      3 * coefficients[3] * value * value;

  static CubicPolynomial? fit(List<double> x, List<double> y) {
    if (x.length != y.length ||
        x.length < 4 ||
        x.any((value) => !value.isFinite) ||
        y.any((value) => !value.isFinite)) {
      return null;
    }
    final mean = x.reduce((sum, value) => sum + value) / x.length;
    final scale = x.fold(
      0.0,
      (largest, value) => math.max(largest, (value - mean).abs()),
    );
    if (scale <= absoluteEpsilon) {
      return null;
    }
    final normalized = x
        .map((value) => (value - mean) / scale)
        .toList(growable: false);
    final coefficients = _HouseholderQr.solve(
      List<List<double>>.generate(
        x.length,
        (row) => <double>[
          1,
          normalized[row],
          normalized[row] * normalized[row],
          normalized[row] * normalized[row] * normalized[row],
        ],
      ),
      y,
    );
    if (coefficients == null) {
      return null;
    }
    final inverseScale = 1 / scale;
    final inverseScaleSquared = inverseScale * inverseScale;
    final inverseScaleCubed = inverseScaleSquared * inverseScale;
    final meanSquared = mean * mean;
    final meanCubed = meanSquared * mean;
    return CubicPolynomial(<double>[
      coefficients[0] -
          coefficients[1] * mean * inverseScale +
          coefficients[2] * meanSquared * inverseScaleSquared -
          coefficients[3] * meanCubed * inverseScaleCubed,
      coefficients[1] * inverseScale -
          2 * coefficients[2] * mean * inverseScaleSquared +
          3 * coefficients[3] * meanSquared * inverseScaleCubed,
      coefficients[2] * inverseScaleSquared -
          3 * coefficients[3] * mean * inverseScaleCubed,
      coefficients[3] * inverseScaleCubed,
    ]);
  }
}

class QuadraticPolynomial {
  const QuadraticPolynomial(this.coefficients);

  final List<double> coefficients;

  double call(double value) =>
      coefficients[0] +
      coefficients[1] * value +
      coefficients[2] * value * value;

  double derivative(double value) =>
      coefficients[1] + 2 * coefficients[2] * value;

  static QuadraticPolynomial? fit(List<double> x, List<double> y) {
    if (x.length != y.length ||
        x.length < 3 ||
        x.any((value) => !value.isFinite) ||
        y.any((value) => !value.isFinite)) {
      return null;
    }
    final mean = x.reduce((sum, value) => sum + value) / x.length;
    final scale = x.fold(
      0.0,
      (largest, value) => math.max(largest, (value - mean).abs()),
    );
    if (scale <= absoluteEpsilon) return null;
    final normalized = x
        .map((value) => (value - mean) / scale)
        .toList(growable: false);
    final coefficients = _HouseholderQr.solve(
      List<List<double>>.generate(
        x.length,
        (row) => <double>[
          1,
          normalized[row],
          normalized[row] * normalized[row],
        ],
      ),
      y,
    );
    if (coefficients == null) return null;
    final inverseScale = 1 / scale;
    final inverseScaleSquared = inverseScale * inverseScale;
    return QuadraticPolynomial(<double>[
      coefficients[0] -
          coefficients[1] * mean * inverseScale +
          coefficients[2] * mean * mean * inverseScaleSquared,
      coefficients[1] * inverseScale -
          2 * coefficients[2] * mean * inverseScaleSquared,
      coefficients[2] * inverseScaleSquared,
    ]);
  }
}

class LinearFit {
  const LinearFit({
    required this.intercept,
    required this.slope,
    required this.rss,
  });

  final double intercept;
  final double slope;
  final double rss;

  static LinearFit? fit(List<double> x, List<double> y) {
    if (x.length != y.length ||
        x.length < 2 ||
        x.any((value) => !value.isFinite) ||
        y.any((value) => !value.isFinite)) {
      return null;
    }
    final coefficients = _HouseholderQr.solve(
      List<List<double>>.generate(x.length, (index) => <double>[1, x[index]]),
      y,
    );
    if (coefficients == null) {
      return null;
    }
    final intercept = coefficients[0];
    final slope = coefficients[1];
    final rss = List.generate(x.length, (index) => index).fold(
      0.0,
      (sum, index) =>
          sum + math.pow(y[index] - (intercept + slope * x[index]), 2),
    );
    return LinearFit(intercept: intercept, slope: slope, rss: rss);
  }
}

class _HouseholderQr {
  static List<double>? solve(List<List<double>> design, List<double> values) {
    if (design.isEmpty || design.length != values.length) {
      return null;
    }
    final rows = design.length;
    final columns = design.first.length;
    if (rows < columns || design.any((row) => row.length != columns)) {
      return null;
    }
    final matrix = design.map((row) => List<double>.from(row)).toList();
    final transformedValues = List<double>.from(values);
    for (var column = 0; column < columns; column++) {
      var norm = 0.0;
      for (var row = column; row < rows; row++) {
        norm = _hypotenuse(norm, matrix[row][column]);
      }
      if (norm <= absoluteEpsilon) {
        return null;
      }
      final sign = matrix[column][column] >= 0 ? 1.0 : -1.0;
      final vector = List<double>.filled(rows - column, 0);
      vector[0] = matrix[column][column] + sign * norm;
      for (var row = column + 1; row < rows; row++) {
        vector[row - column] = matrix[row][column];
      }
      final vectorNormSquared = vector.fold(
        0.0,
        (sum, value) => sum + value * value,
      );
      if (vectorNormSquared <= absoluteEpsilon) {
        return null;
      }
      for (var targetColumn = column; targetColumn < columns; targetColumn++) {
        var dot = 0.0;
        for (var row = column; row < rows; row++) {
          dot += vector[row - column] * matrix[row][targetColumn];
        }
        final factor = 2 * dot / vectorNormSquared;
        for (var row = column; row < rows; row++) {
          matrix[row][targetColumn] -= factor * vector[row - column];
        }
      }
      var valueDot = 0.0;
      for (var row = column; row < rows; row++) {
        valueDot += vector[row - column] * transformedValues[row];
      }
      final valueFactor = 2 * valueDot / vectorNormSquared;
      for (var row = column; row < rows; row++) {
        transformedValues[row] -= valueFactor * vector[row - column];
      }
    }
    final solution = List<double>.filled(columns, 0);
    for (var row = columns - 1; row >= 0; row--) {
      var remainder = transformedValues[row];
      for (var column = row + 1; column < columns; column++) {
        remainder -= matrix[row][column] * solution[column];
      }
      if (matrix[row][row].abs() <= absoluteEpsilon) {
        return null;
      }
      solution[row] = remainder / matrix[row][row];
    }
    return solution.every((value) => value.isFinite) ? solution : null;
  }
}

List<double> quadraticRoots(double a, double b, double c) {
  if (a.abs() < absoluteEpsilon) {
    return b.abs() < absoluteEpsilon ? const [] : [-c / b];
  }
  final discriminant = b * b - 4 * a * c;
  if (discriminant < 0) return const [];
  final root = math.sqrt(discriminant);
  return [(-b - root) / (2 * a), (-b + root) / (2 * a)];
}
