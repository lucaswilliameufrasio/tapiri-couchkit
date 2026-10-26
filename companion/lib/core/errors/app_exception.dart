sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A TV nao respondeu (desligada, outra rede, app fechado, porta mudou).
class TvUnreachableException extends AppException {
  const TvUnreachableException([super.message = 'Não consegui falar com a TV']);
}

/// Token recusado (403).
class TvUnauthorizedException extends AppException {
  const TvUnauthorizedException([super.message = 'Token recusado pela TV']);
}

class TvRequestException extends AppException {
  const TvRequestException(super.message, {this.status});

  final int? status;
}

class InvalidConnectionUrlException extends AppException {
  const InvalidConnectionUrlException([
    super.message = 'Endereço inválido: falta o token (?k=...)',
  ]);
}
