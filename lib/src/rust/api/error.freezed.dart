// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApiError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError()';
}


}

/// @nodoc
class $ApiErrorCopyWith<$Res>  {
$ApiErrorCopyWith(ApiError _, $Res Function(ApiError) __);
}


/// Adds pattern-matching-related methods to [ApiError].
extension ApiErrorPatterns on ApiError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ApiError_NotLoggedIn value)?  notLoggedIn,TResult Function( ApiError_NoPlayableUrl value)?  noPlayableUrl,TResult Function( ApiError_UnsupportedFormat value)?  unsupportedFormat,TResult Function( ApiError_UnverifiedFormat value)?  unverifiedFormat,TResult Function( ApiError_LoginFailed value)?  loginFailed,TResult Function( ApiError_InvalidCookie value)?  invalidCookie,TResult Function( ApiError_ServerError value)?  serverError,TResult Function( ApiError_BadResponse value)?  badResponse,TResult Function( ApiError_Network value)?  network,TResult Function( ApiError_Internal value)?  internal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ApiError_NotLoggedIn() when notLoggedIn != null:
return notLoggedIn(_that);case ApiError_NoPlayableUrl() when noPlayableUrl != null:
return noPlayableUrl(_that);case ApiError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case ApiError_UnverifiedFormat() when unverifiedFormat != null:
return unverifiedFormat(_that);case ApiError_LoginFailed() when loginFailed != null:
return loginFailed(_that);case ApiError_InvalidCookie() when invalidCookie != null:
return invalidCookie(_that);case ApiError_ServerError() when serverError != null:
return serverError(_that);case ApiError_BadResponse() when badResponse != null:
return badResponse(_that);case ApiError_Network() when network != null:
return network(_that);case ApiError_Internal() when internal != null:
return internal(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ApiError_NotLoggedIn value)  notLoggedIn,required TResult Function( ApiError_NoPlayableUrl value)  noPlayableUrl,required TResult Function( ApiError_UnsupportedFormat value)  unsupportedFormat,required TResult Function( ApiError_UnverifiedFormat value)  unverifiedFormat,required TResult Function( ApiError_LoginFailed value)  loginFailed,required TResult Function( ApiError_InvalidCookie value)  invalidCookie,required TResult Function( ApiError_ServerError value)  serverError,required TResult Function( ApiError_BadResponse value)  badResponse,required TResult Function( ApiError_Network value)  network,required TResult Function( ApiError_Internal value)  internal,}){
final _that = this;
switch (_that) {
case ApiError_NotLoggedIn():
return notLoggedIn(_that);case ApiError_NoPlayableUrl():
return noPlayableUrl(_that);case ApiError_UnsupportedFormat():
return unsupportedFormat(_that);case ApiError_UnverifiedFormat():
return unverifiedFormat(_that);case ApiError_LoginFailed():
return loginFailed(_that);case ApiError_InvalidCookie():
return invalidCookie(_that);case ApiError_ServerError():
return serverError(_that);case ApiError_BadResponse():
return badResponse(_that);case ApiError_Network():
return network(_that);case ApiError_Internal():
return internal(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ApiError_NotLoggedIn value)?  notLoggedIn,TResult? Function( ApiError_NoPlayableUrl value)?  noPlayableUrl,TResult? Function( ApiError_UnsupportedFormat value)?  unsupportedFormat,TResult? Function( ApiError_UnverifiedFormat value)?  unverifiedFormat,TResult? Function( ApiError_LoginFailed value)?  loginFailed,TResult? Function( ApiError_InvalidCookie value)?  invalidCookie,TResult? Function( ApiError_ServerError value)?  serverError,TResult? Function( ApiError_BadResponse value)?  badResponse,TResult? Function( ApiError_Network value)?  network,TResult? Function( ApiError_Internal value)?  internal,}){
final _that = this;
switch (_that) {
case ApiError_NotLoggedIn() when notLoggedIn != null:
return notLoggedIn(_that);case ApiError_NoPlayableUrl() when noPlayableUrl != null:
return noPlayableUrl(_that);case ApiError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat(_that);case ApiError_UnverifiedFormat() when unverifiedFormat != null:
return unverifiedFormat(_that);case ApiError_LoginFailed() when loginFailed != null:
return loginFailed(_that);case ApiError_InvalidCookie() when invalidCookie != null:
return invalidCookie(_that);case ApiError_ServerError() when serverError != null:
return serverError(_that);case ApiError_BadResponse() when badResponse != null:
return badResponse(_that);case ApiError_Network() when network != null:
return network(_that);case ApiError_Internal() when internal != null:
return internal(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notLoggedIn,TResult Function()?  noPlayableUrl,TResult Function()?  unsupportedFormat,TResult Function()?  unverifiedFormat,TResult Function( String detail)?  loginFailed,TResult Function( String missing)?  invalidCookie,TResult Function( String api,  String code)?  serverError,TResult Function( String detail)?  badResponse,TResult Function( String detail)?  network,TResult Function( String detail)?  internal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ApiError_NotLoggedIn() when notLoggedIn != null:
return notLoggedIn();case ApiError_NoPlayableUrl() when noPlayableUrl != null:
return noPlayableUrl();case ApiError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat();case ApiError_UnverifiedFormat() when unverifiedFormat != null:
return unverifiedFormat();case ApiError_LoginFailed() when loginFailed != null:
return loginFailed(_that.detail);case ApiError_InvalidCookie() when invalidCookie != null:
return invalidCookie(_that.missing);case ApiError_ServerError() when serverError != null:
return serverError(_that.api,_that.code);case ApiError_BadResponse() when badResponse != null:
return badResponse(_that.detail);case ApiError_Network() when network != null:
return network(_that.detail);case ApiError_Internal() when internal != null:
return internal(_that.detail);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notLoggedIn,required TResult Function()  noPlayableUrl,required TResult Function()  unsupportedFormat,required TResult Function()  unverifiedFormat,required TResult Function( String detail)  loginFailed,required TResult Function( String missing)  invalidCookie,required TResult Function( String api,  String code)  serverError,required TResult Function( String detail)  badResponse,required TResult Function( String detail)  network,required TResult Function( String detail)  internal,}) {final _that = this;
switch (_that) {
case ApiError_NotLoggedIn():
return notLoggedIn();case ApiError_NoPlayableUrl():
return noPlayableUrl();case ApiError_UnsupportedFormat():
return unsupportedFormat();case ApiError_UnverifiedFormat():
return unverifiedFormat();case ApiError_LoginFailed():
return loginFailed(_that.detail);case ApiError_InvalidCookie():
return invalidCookie(_that.missing);case ApiError_ServerError():
return serverError(_that.api,_that.code);case ApiError_BadResponse():
return badResponse(_that.detail);case ApiError_Network():
return network(_that.detail);case ApiError_Internal():
return internal(_that.detail);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notLoggedIn,TResult? Function()?  noPlayableUrl,TResult? Function()?  unsupportedFormat,TResult? Function()?  unverifiedFormat,TResult? Function( String detail)?  loginFailed,TResult? Function( String missing)?  invalidCookie,TResult? Function( String api,  String code)?  serverError,TResult? Function( String detail)?  badResponse,TResult? Function( String detail)?  network,TResult? Function( String detail)?  internal,}) {final _that = this;
switch (_that) {
case ApiError_NotLoggedIn() when notLoggedIn != null:
return notLoggedIn();case ApiError_NoPlayableUrl() when noPlayableUrl != null:
return noPlayableUrl();case ApiError_UnsupportedFormat() when unsupportedFormat != null:
return unsupportedFormat();case ApiError_UnverifiedFormat() when unverifiedFormat != null:
return unverifiedFormat();case ApiError_LoginFailed() when loginFailed != null:
return loginFailed(_that.detail);case ApiError_InvalidCookie() when invalidCookie != null:
return invalidCookie(_that.missing);case ApiError_ServerError() when serverError != null:
return serverError(_that.api,_that.code);case ApiError_BadResponse() when badResponse != null:
return badResponse(_that.detail);case ApiError_Network() when network != null:
return network(_that.detail);case ApiError_Internal() when internal != null:
return internal(_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class ApiError_NotLoggedIn extends ApiError {
  const ApiError_NotLoggedIn(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_NotLoggedIn);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.notLoggedIn()';
}


}




/// @nodoc


class ApiError_NoPlayableUrl extends ApiError {
  const ApiError_NoPlayableUrl(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_NoPlayableUrl);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.noPlayableUrl()';
}


}




/// @nodoc


class ApiError_UnsupportedFormat extends ApiError {
  const ApiError_UnsupportedFormat(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_UnsupportedFormat);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.unsupportedFormat()';
}


}




/// @nodoc


class ApiError_UnverifiedFormat extends ApiError {
  const ApiError_UnverifiedFormat(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_UnverifiedFormat);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiError.unverifiedFormat()';
}


}




/// @nodoc


class ApiError_LoginFailed extends ApiError {
  const ApiError_LoginFailed({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_LoginFailedCopyWith<ApiError_LoginFailed> get copyWith => _$ApiError_LoginFailedCopyWithImpl<ApiError_LoginFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_LoginFailed&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,detail);
}

@override
String toString() {
    return 'ApiError.loginFailed(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ApiError_LoginFailedCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_LoginFailedCopyWith(ApiError_LoginFailed value, $Res Function(ApiError_LoginFailed) _then) = _$ApiError_LoginFailedCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$ApiError_LoginFailedCopyWithImpl<$Res>
    implements $ApiError_LoginFailedCopyWith<$Res> {
  _$ApiError_LoginFailedCopyWithImpl(this._self, this._then);

  final ApiError_LoginFailed _self;
  final $Res Function(ApiError_LoginFailed) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(ApiError_LoginFailed(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_InvalidCookie extends ApiError {
  const ApiError_InvalidCookie({required this.missing}): super._();
  

 final  String missing;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_InvalidCookieCopyWith<ApiError_InvalidCookie> get copyWith => _$ApiError_InvalidCookieCopyWithImpl<ApiError_InvalidCookie>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_InvalidCookie&&(identical(other.missing, missing) || other.missing == missing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,missing);
}

@override
String toString() {
    return 'ApiError.invalidCookie(missing: $missing)';
}


}

/// @nodoc
abstract mixin class $ApiError_InvalidCookieCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_InvalidCookieCopyWith(ApiError_InvalidCookie value, $Res Function(ApiError_InvalidCookie) _then) = _$ApiError_InvalidCookieCopyWithImpl;
@useResult
$Res call({
 String missing
});




}
/// @nodoc
class _$ApiError_InvalidCookieCopyWithImpl<$Res>
    implements $ApiError_InvalidCookieCopyWith<$Res> {
  _$ApiError_InvalidCookieCopyWithImpl(this._self, this._then);

  final ApiError_InvalidCookie _self;
  final $Res Function(ApiError_InvalidCookie) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? missing = null,}) {
  return _then(ApiError_InvalidCookie(
missing: null == missing ? _self.missing : missing // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_ServerError extends ApiError {
  const ApiError_ServerError({required this.api, required this.code}): super._();
  

 final  String api;
 final  String code;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_ServerErrorCopyWith<ApiError_ServerError> get copyWith => _$ApiError_ServerErrorCopyWithImpl<ApiError_ServerError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_ServerError&&(identical(other.api, api) || other.api == api)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode {
    return Object.hash(runtimeType,api,code);
}

@override
String toString() {
    return 'ApiError.serverError(api: $api, code: $code)';
}


}

/// @nodoc
abstract mixin class $ApiError_ServerErrorCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_ServerErrorCopyWith(ApiError_ServerError value, $Res Function(ApiError_ServerError) _then) = _$ApiError_ServerErrorCopyWithImpl;
@useResult
$Res call({
 String api, String code
});




}
/// @nodoc
class _$ApiError_ServerErrorCopyWithImpl<$Res>
    implements $ApiError_ServerErrorCopyWith<$Res> {
  _$ApiError_ServerErrorCopyWithImpl(this._self, this._then);

  final ApiError_ServerError _self;
  final $Res Function(ApiError_ServerError) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? api = null,Object? code = null,}) {
  return _then(ApiError_ServerError(
api: null == api ? _self.api : api // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_BadResponse extends ApiError {
  const ApiError_BadResponse({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_BadResponseCopyWith<ApiError_BadResponse> get copyWith => _$ApiError_BadResponseCopyWithImpl<ApiError_BadResponse>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_BadResponse&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,detail);
}

@override
String toString() {
    return 'ApiError.badResponse(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ApiError_BadResponseCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_BadResponseCopyWith(ApiError_BadResponse value, $Res Function(ApiError_BadResponse) _then) = _$ApiError_BadResponseCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$ApiError_BadResponseCopyWithImpl<$Res>
    implements $ApiError_BadResponseCopyWith<$Res> {
  _$ApiError_BadResponseCopyWithImpl(this._self, this._then);

  final ApiError_BadResponse _self;
  final $Res Function(ApiError_BadResponse) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(ApiError_BadResponse(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_Network extends ApiError {
  const ApiError_Network({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_NetworkCopyWith<ApiError_Network> get copyWith => _$ApiError_NetworkCopyWithImpl<ApiError_Network>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_Network&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,detail);
}

@override
String toString() {
    return 'ApiError.network(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ApiError_NetworkCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_NetworkCopyWith(ApiError_Network value, $Res Function(ApiError_Network) _then) = _$ApiError_NetworkCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$ApiError_NetworkCopyWithImpl<$Res>
    implements $ApiError_NetworkCopyWith<$Res> {
  _$ApiError_NetworkCopyWithImpl(this._self, this._then);

  final ApiError_Network _self;
  final $Res Function(ApiError_Network) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(ApiError_Network(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ApiError_Internal extends ApiError {
  const ApiError_Internal({required this.detail}): super._();
  

 final  String detail;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiError_InternalCopyWith<ApiError_Internal> get copyWith => _$ApiError_InternalCopyWithImpl<ApiError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiError_Internal&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode {
    return Object.hash(runtimeType,detail);
}

@override
String toString() {
    return 'ApiError.internal(detail: $detail)';
}


}

/// @nodoc
abstract mixin class $ApiError_InternalCopyWith<$Res> implements $ApiErrorCopyWith<$Res> {
  factory $ApiError_InternalCopyWith(ApiError_Internal value, $Res Function(ApiError_Internal) _then) = _$ApiError_InternalCopyWithImpl;
@useResult
$Res call({
 String detail
});




}
/// @nodoc
class _$ApiError_InternalCopyWithImpl<$Res>
    implements $ApiError_InternalCopyWith<$Res> {
  _$ApiError_InternalCopyWithImpl(this._self, this._then);

  final ApiError_Internal _self;
  final $Res Function(ApiError_Internal) _then;

/// Create a copy of ApiError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? detail = null,}) {
  return _then(ApiError_Internal(
detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
