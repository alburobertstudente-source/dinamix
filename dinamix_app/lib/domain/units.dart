import 'dart:math' as math;

import 'sensor_kind.dart';

enum AccUnit { mg, g, ms2 }

enum GyroUnit { dps, rads }

enum MagUnit { mGa, uT }

enum TempUnit { celsius, fahrenheit }

enum PressureUnit { hPa, kPa }

/// Standard gravity, used only for display conversions.
const double standardGravity = 9.80665;

/// Conversion from canonical units to the ones selected by the user.
/// Only the UI uses it: database and exports always stay canonical.
class UnitPrefs {
  const UnitPrefs({
    this.acc = AccUnit.mg,
    this.gyro = GyroUnit.dps,
    this.mag = MagUnit.mGa,
    this.temp = TempUnit.celsius,
    this.pressure = PressureUnit.hPa,
  });

  final AccUnit acc;
  final GyroUnit gyro;
  final MagUnit mag;
  final TempUnit temp;
  final PressureUnit pressure;

  double convert(SensorKind kind, int channel, double value) {
    switch (kind) {
      case SensorKind.accelerometer:
        return switch (acc) {
          AccUnit.mg => value,
          AccUnit.g => value / 1000.0,
          AccUnit.ms2 => value / 1000.0 * standardGravity,
        };
      case SensorKind.gyroscope:
        return gyro == GyroUnit.dps ? value : value * math.pi / 180.0;
      case SensorKind.magnetometer:
        // 1 Gauss = 100 uT, therefore 1 mGa = 0.1 uT.
        return mag == MagUnit.mGa ? value : value * 0.1;
      case SensorKind.temperature:
      case SensorKind.temperature2:
        return temp == TempUnit.celsius ? value : value * 9.0 / 5.0 + 32.0;
      case SensorKind.pressure:
        return pressure == PressureUnit.hPa ? value : value / 10.0;
      default:
        return value;
    }
  }

  String unit(SensorKind kind, int channel) {
    switch (kind) {
      case SensorKind.accelerometer:
        return switch (acc) {
          AccUnit.mg => 'mg',
          AccUnit.g => 'g',
          AccUnit.ms2 => 'm/s²',
        };
      case SensorKind.gyroscope:
        return gyro == GyroUnit.dps ? 'dps' : 'rad/s';
      case SensorKind.magnetometer:
        return mag == MagUnit.mGa ? 'mGa' : 'µT';
      case SensorKind.temperature:
      case SensorKind.temperature2:
        return temp == TempUnit.celsius ? '°C' : '°F';
      case SensorKind.pressure:
        return pressure == PressureUnit.hPa ? 'hPa' : 'kPa';
      default:
        return kind.channels[channel].unit;
    }
  }

  /// Decimals that suit the unit without showing false precision.
  int decimals(SensorKind kind, int channel) {
    switch (kind) {
      case SensorKind.accelerometer:
        return acc == AccUnit.mg ? 0 : 3;
      case SensorKind.gyroscope:
        return gyro == GyroUnit.dps ? 1 : 3;
      case SensorKind.magnetometer:
        return mag == MagUnit.mGa ? 0 : 1;
      case SensorKind.temperature:
      case SensorKind.temperature2:
      case SensorKind.humidity:
        return 1;
      case SensorKind.pressure:
        return 2;
      case SensorKind.quaternion:
        return 4;
      case SensorKind.euler:
      case SensorKind.compass:
        return 1;
      case SensorKind.battery:
        return channel == 1 ? 3 : (channel == 3 ? 0 : 1);
      default:
        return 0;
    }
  }

  String format(SensorKind kind, int channel, double value) {
    if (value.isNaN) return '—';
    return convert(kind, channel, value).toStringAsFixed(decimals(kind, channel));
  }
}
