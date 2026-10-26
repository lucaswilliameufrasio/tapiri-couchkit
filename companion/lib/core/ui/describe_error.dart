import 'package:flutter/material.dart';

import 'package:couchkit_remote/core/errors/app_exception.dart';

String describeError(Object error) {
  if (error is AppException) {
    return error.message;
  }
  return 'Algo deu errado: $error';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Roda uma acao da TV e mostra o erro (se houver) num snackbar.
Future<T?> guarded<T>(BuildContext context, Future<T> Function() action) async {
  try {
    return await action();
  } catch (error) {
    if (context.mounted) {
      showMessage(context, describeError(error));
    }
    return null;
  }
}
