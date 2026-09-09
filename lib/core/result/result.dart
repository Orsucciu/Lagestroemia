// A minimal Result type for fallible operations.
//
// We avoid `dart:io`'s `Either` (not a thing — we used to come from languages
// that have one) and instead use a sealed-union of [Ok] / [Err]. This keeps
// error handling explicit at every call site while still being ergonomic with
// `switch` expressions in Dart 3.

/// Base class for fallible operations.
///
/// Use:
/// ```dart
/// Result<User, ApiError> load() {
///   if (ok) return Ok(user);
///   return Err(ApiError('no user'));
/// }
///
/// final result = load();
/// switch (result) {
///   case Ok(:final value): print(value);
///   case Err(:final error): print(error);
/// }
/// ```
sealed class Result<T, E> {
  const Result();

  /// `true` if this is an [Ok].
  bool get isOk => this is Ok<T, E>;

  /// `true` if this is an [Err].
  bool get isErr => this is Err<T, E>;

  /// Returns the value if [Ok], or throws if [Err].
  T unwrap() {
    final self = this;
    if (self is Ok<T, E>) return self.value;
    if (self is Err<T, E>) {
      throw StateError('Result.unwrap() on Err: ${self.error}');
    }
    throw StateError('Result.unwrap() on unknown subtype');
  }

  /// Returns the value if [Ok], or [fallback] if [Err].
  T unwrapOr(T fallback) {
    final self = this;
    if (self is Ok<T, E>) return self.value;
    return fallback;
  }

  /// Returns the error if [Err], or throws if [Ok].
  E unwrapErr() {
    final self = this;
    if (self is Err<T, E>) return self.error;
    if (self is Ok<T, E>) {
      throw StateError('Result.unwrapErr() on Ok: ${self.value}');
    }
    throw StateError('Result.unwrapErr() on unknown subtype');
  }

  /// Returns the error if [Err], or null if [Ok].
  E? get error => this is Err<T, E> ? (this as Err<T, E>).error : null;

  /// Maps [Ok<T,E>] to [Ok<U,E>] using [f]. [Err] passes through unchanged.
  Result<U, E> map<U>(U Function(T) f) {
    final self = this;
    if (self is Ok<T, E>) return Ok<U, E>(f(self.value));
    if (self is Err<T, E>) return Err<U, E>(self.error);
    throw StateError('Result.map on unknown subtype');
  }

  /// Maps [Err<T,E>] to [Err<T,F>] using [f]. [Ok] passes through unchanged.
  Result<T, F> mapErr<F>(F Function(E) f) {
    final self = this;
    if (self is Err<T, E>) return Err<T, F>(f(self.error));
    if (self is Ok<T, E>) return Ok<T, F>(self.value);
    throw StateError('Result.mapErr on unknown subtype');
  }
}

/// Success branch of [Result].
final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);
  final T value;
  @override
  String toString() => 'Ok($value)';
}

/// Failure branch of [Result].
final class Err<T, E> extends Result<T, E> {
  const Err(this.error);
  final E error;
  @override
  String toString() => 'Err($error)';
}
