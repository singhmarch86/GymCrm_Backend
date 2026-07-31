/// Shared form-field validators. Pure functions of the form
/// `String? Function(String?)`, so they drop straight into
/// `TextFormField.validator`.
class Validators {
  Validators._();

  static final RegExp _phone = RegExp(r'^[0-9]{10}$');
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Expects a 10-digit phone number (no country code, no separators —
  /// matches how phone numbers are stored throughout this app, e.g. the
  /// seeded owner login `9876543210`).
  static String? phone(String? value) {
    final requiredError = required(value, 'Phone number');
    if (requiredError != null) return requiredError;
    if (!_phone.hasMatch(value!.trim())) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  /// Same as [phone], but returns null (valid) for an empty value — for
  /// optional phone fields.
  static String? phoneOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return phone(value);
  }

  static String? email(String? value) {
    final requiredError = required(value, 'Email');
    if (requiredError != null) return requiredError;
    if (!_email.hasMatch(value!.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Same as [email], but returns null (valid) for an empty value — for
  /// optional email fields.
  static String? emailOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return email(value);
  }

  static String? positiveNumber(String? value, [String fieldName = 'Value']) {
    final requiredError = required(value, fieldName);
    if (requiredError != null) return requiredError;
    final parsed = double.tryParse(value!.trim());
    if (parsed == null) return '$fieldName must be a number';
    if (parsed <= 0) return '$fieldName must be greater than 0';
    return null;
  }

  static String? positiveInteger(String? value, [String fieldName = 'Value']) {
    final requiredError = required(value, fieldName);
    if (requiredError != null) return requiredError;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null) return '$fieldName must be a whole number';
    if (parsed <= 0) return '$fieldName must be greater than 0';
    return null;
  }
}
