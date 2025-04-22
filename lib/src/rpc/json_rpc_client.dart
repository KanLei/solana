import 'dart:async';

import 'package:dio/dio.dart';
import 'package:solana/src/exceptions/http_exception.dart';
import 'package:solana/src/exceptions/json_rpc_exception.dart';
import 'package:solana/src/rpc/json_rpc_request.dart';

class JsonRpcClient {
  JsonRpcClient(
    this._url, {
    required Map<String, String> customHeaders,
    Dio? http,
  })  : _http = http ?? Dio(),
        _headers = {..._defaultHeaders, ...customHeaders};

  final Dio _http;
  final String _url;
  final Map<String, String> _headers;
  int _lastId = 1;

  Future<List<Map<String, dynamic>>> bulkRequest(
    String method,
    List<List<dynamic>> params,
  ) async {
    final requests = params
        .map(
          (p) => JsonRpcSingleRequest(
            method: method,
            params: p,
            id: (_lastId++).toString(),
          ),
        )
        .toList(growable: false);

    final response = await _postRequest(JsonRpcRequest.bulk(requests));
    if (response is _JsonRpcArrayResponse) {
      final elements = response.array;

      return elements
          .map((_JsonRpcObjectResponse item) => item.data)
          .toList(growable: false);
    }

    throw const FormatException('unexpected jsonrpc response type');
  }

  /// Calls the [method] jsonrpc-2.0 method with [params] parameters
  Future<Map<String, dynamic>> request(
    String method, {
    List<dynamic>? params,
  }) async {
    final request = JsonRpcSingleRequest(
      id: (_lastId++).toString(),
      method: method,
      params: params,
    );

    final response = await _postRequest(request);
    if (response is _JsonRpcObjectResponse) {
      return response.data;
    }

    throw const FormatException('unexpected jsonrpc response type');
  }

  Future<_JsonRpcResponse> _postRequest(
    JsonRpcRequest request,
  ) async {
    final body = request.toJson();
    final response = await _http.post(
      _url,
      data: body,
      options: Options(headers: _headers),
    );
    if (response.statusCode == 200) {
      return _JsonRpcResponse._parse(response.data);
    }

    throw HttpException(response.statusCode ?? -1, response.toString());
  }
}

abstract class _JsonRpcResponse {
  const factory _JsonRpcResponse._object(Map<String, dynamic> data) =
      _JsonRpcObjectResponse;

  const factory _JsonRpcResponse._array(List<_JsonRpcObjectResponse> list) =
      _JsonRpcArrayResponse;

  factory _JsonRpcResponse._fromObject(Map<String, dynamic> data) {
    if (data['jsonrpc'] != '2.0') {
      throw const FormatException('invalid jsonrpc-2.0 response');
    }
    if (data['error'] != null) {
      throw JsonRpcException.fromJson(data['error'] as Map<String, dynamic>);
    }
    if (!data.containsKey('result')) {
      throw const FormatException(
        'object has no result field, invalid jsonrpc-2.0',
      );
    }

    return _JsonRpcResponse._object(data);
  }

  factory _JsonRpcResponse._parse(dynamic response) {
    if (response is List<dynamic>) {
      return _JsonRpcResponse._array(
        response.map((dynamic r) {
          if (r is Map<String, dynamic>) {
            return _JsonRpcObjectResponse(r);
          }

          throw const FormatException('cannot parse the jsonrpc response');
        }).toList(growable: false),
      );
    } else if (response is Map<String, dynamic>) {
      return _JsonRpcResponse._fromObject(response);
    }

    throw const FormatException('cannot parse the jsonrpc response');
  }
}

class _JsonRpcObjectResponse implements _JsonRpcResponse {
  const _JsonRpcObjectResponse(this.data);

  final Map<String, dynamic> data;
}

class _JsonRpcArrayResponse implements _JsonRpcResponse {
  const _JsonRpcArrayResponse(this.array);

  final List<_JsonRpcObjectResponse> array;
}

const _defaultHeaders = <String, String>{
  'Content-Type': 'application/json',
};
