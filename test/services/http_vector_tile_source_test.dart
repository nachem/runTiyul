import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trail_runner/services/vector_tile_source.dart';

void main() {
  test('resolves a TileJSON endpoint and fetches tiles', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/planet')) {
        return http.Response(
          jsonEncode({
            'tiles': ['https://tiles.example/pt/{z}/{x}/{y}.pbf'],
            'minzoom': 0,
            'maxzoom': 14,
          }),
          200,
        );
      }
      if (request.url.path == '/pt/14/8186/5448.pbf') {
        return http.Response.bytes([1, 2, 3, 4], 200);
      }
      return http.Response('not found', 404);
    });

    final source = await HttpVectorTileSource.open(
      'https://tiles.example/planet',
      client: client,
    );
    expect(source.minZoom, 0);
    expect(source.maxZoom, 14);

    expect(await source.readTile(14, 8186, 5448), [1, 2, 3, 4]);
    // Beyond the source max zoom: no request is made, returns null.
    expect(await source.readTile(15, 0, 0), isNull);
    // A missing tile is null, not an error.
    expect(await source.readTile(14, 0, 0), isNull);

    await source.close();
  });

  test('accepts a direct z/x/y template', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/pt/10/1/2.pbf') {
        return http.Response.bytes([9, 9], 200);
      }
      return http.Response('nope', 404);
    });

    final source = await HttpVectorTileSource.open(
      'https://tiles.example/pt/{z}/{x}/{y}.pbf',
      client: client,
    );
    expect(source.maxZoom, 14);
    expect(await source.readTile(10, 1, 2), [9, 9]);
    await source.close();
  });

  test('only a tile 404 is missing and is not retried', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('not found', 404);
    });
    addTearDown(client.close);
    final source = await HttpVectorTileSource.open(_template, client: client);
    addTearDown(source.close);

    expect(await source.readTile(10, 1, 2), isNull);
    expect(requests, 1);
  });

  test('out-of-range zooms are missing without making requests', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('unexpected request', 500);
    });
    addTearDown(client.close);
    final source = await HttpVectorTileSource.open(_template, client: client);
    addTearDown(source.close);

    expect(await source.readTile(-1, 0, 0), isNull);
    expect(await source.readTile(15, 0, 0), isNull);
    expect(requests, 0);
  });

  test(
    'decompresses gzip tiles and preserves an empty HTTP 200 payload',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response.bytes(
          requests == 1 ? gzip.encode([9, 9]) : [],
          200,
        );
      });
      addTearDown(client.close);
      final source = await HttpVectorTileSource.open(_template, client: client);
      addTearDown(source.close);

      expect(await source.readTile(10, 1, 2), [9, 9]);
      expect(await source.readTile(10, 1, 3), isEmpty);
      expect(requests, 2);
    },
  );

  for (final tileJson in [true, false]) {
    final kind = tileJson ? 'TileJSON' : 'tile';
    group('$kind reliability (OFF-006, OFF-009)', () {
      for (final status in [429, 500, 503]) {
        testWidgets('recovers from HTTP $status with bounded backoff', (
          tester,
        ) async {
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            return requests < 3
                ? http.Response('temporary failure', status)
                : _successResponse(tileJson);
          });
          addTearDown(client.close);

          final result = _requestVectorData(client, tileJson: tileJson);
          await tester.pump();
          expect(requests, 1);
          await tester.pump(const Duration(milliseconds: 299));
          expect(requests, 1);
          await tester.pump(const Duration(milliseconds: 1));
          expect(requests, 2);
          await tester.pump(const Duration(milliseconds: 599));
          expect(requests, 2);
          await tester.pump(const Duration(milliseconds: 1));
          expect(await result, tileJson ? [5, 14] : [9, 9]);
          expect(requests, 3);
        });

        testWidgets('fails safely after three HTTP $status responses', (
          tester,
        ) async {
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            return http.Response('private response for ${request.url}', status);
          });
          addTearDown(client.close);

          final result = expectLater(
            _requestVectorData(client, tileJson: tileJson),
            _statusFailure(kind, status),
          );
          await tester.pump();
          expect(requests, 1);
          await tester.pump(const Duration(milliseconds: 300));
          expect(requests, 2);
          await tester.pump(const Duration(milliseconds: 600));
          await result;
          expect(requests, 3);
          await tester.pump(const Duration(minutes: 1));
          expect(requests, 3);
        });
      }

      for (final status in [
        204,
        206,
        302,
        400,
        401,
        403,
        408,
        410,
        if (tileJson) 404,
      ]) {
        test(
          'fails HTTP $status immediately without exposing provider data',
          () async {
            var requests = 0;
            final client = MockClient((request) async {
              requests++;
              return http.Response(
                'private response for ${request.url}',
                status,
                reasonPhrase: 'private provider details',
              );
            });
            addTearDown(client.close);

            await expectLater(
              _requestVectorData(client, tileJson: tileJson),
              _statusFailure(kind, status),
            );
            expect(requests, 1);
          },
        );
      }

      final networkErrors = <String, Exception>{
        'client': http.ClientException(
          'private provider details',
          Uri.parse(_endpoint),
        ),
        'socket': const SocketException('private provider hostname'),
        'HTTP I/O': HttpException(
          'private provider details',
          uri: Uri.parse(_endpoint),
        ),
      };
      for (final failure in networkErrors.entries) {
        testWidgets('recovers from a ${failure.key} failure', (tester) async {
          var requests = 0;
          final client = MockClient((request) async {
            if (++requests == 1) throw failure.value;
            return _successResponse(tileJson);
          });
          addTearDown(client.close);

          final result = _requestVectorData(client, tileJson: tileJson);
          await tester.pump();
          expect(requests, 1);
          await tester.pump(const Duration(milliseconds: 300));
          expect(await result, tileJson ? [5, 14] : [9, 9]);
          expect(requests, 2);
        });

        testWidgets('fails safely after three ${failure.key} failures', (
          tester,
        ) async {
          var requests = 0;
          final client = MockClient((request) async {
            requests++;
            throw failure.value;
          });
          addTearDown(client.close);

          final result = expectLater(
            _requestVectorData(client, tileJson: tileJson),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Vector $kind request failed (network error).',
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pump(const Duration(milliseconds: 600));
          await result;
          expect(requests, 3);
        });
      }

      test('does not retry unrelated errors', () async {
        var requests = 0;
        final failure = StateError('unexpected programming error');
        final client = MockClient((request) async {
          requests++;
          throw failure;
        });
        addTearDown(client.close);

        await expectLater(
          _requestVectorData(client, tileJson: tileJson),
          throwsA(same(failure)),
        );
        expect(requests, 1);
      });

      testWidgets(
        'recovers after a timed-out request and ignores its late result',
        (tester) async {
          var requests = 0;
          final pending = Completer<http.Response>();
          final client = MockClient((request) async {
            if (++requests == 1) return pending.future;
            return _successResponse(tileJson);
          });
          addTearDown(client.close);

          final result = _requestVectorData(client, tileJson: tileJson);
          await tester.pump();
          expect(requests, 1);
          await tester.pump(const Duration(seconds: 15));
          expect(requests, 1);
          await tester.pump(const Duration(milliseconds: 300));
          expect(await result, tileJson ? [5, 14] : [9, 9]);
          expect(requests, 2);
          pending.complete(http.Response('late failure', 401));
          await tester.pump();
          expect(requests, 2);
        },
      );

      for (final stalledBody in [false, true]) {
        testWidgets(
          'times out stalled response ${stalledBody ? 'bodies' : 'headers'} after three attempts',
          (tester) async {
            var requests = 0;
            final pendingResponses = <Completer<http.Response>>[];
            final pendingBodies = <Completer<List<int>>>[];
            final client = stalledBody
                ? MockClient.streaming((request, body) async {
                    requests++;
                    final pending = Completer<List<int>>();
                    pendingBodies.add(pending);
                    return http.StreamedResponse(
                      Stream.fromFuture(pending.future),
                      200,
                    );
                  })
                : MockClient((request) {
                    requests++;
                    final pending = Completer<http.Response>();
                    pendingResponses.add(pending);
                    return pending.future;
                  });
            addTearDown(client.close);

            final result = expectLater(
              _requestVectorData(client, tileJson: tileJson),
              throwsA(
                isA<TimeoutException>().having(
                  (error) => error.message,
                  'message',
                  'Vector $kind request timed out.',
                ),
              ),
            );
            await tester.pump();
            for (var attempt = 0; attempt < 3; attempt++) {
              expect(requests, attempt + 1);
              await tester.pump(const Duration(seconds: 14));
              expect(requests, attempt + 1);
              await tester.pump(const Duration(seconds: 1));
              if (attempt < 2) {
                await tester.pump(Duration(milliseconds: 300 * (1 << attempt)));
              }
            }
            await result;
            expect(requests, 3);
            for (final pending in pendingResponses) {
              pending.complete(_successResponse(tileJson));
            }
            for (final pending in pendingBodies) {
              pending.complete(_successResponse(tileJson).bodyBytes);
            }
            await tester.pump();
          },
        );
      }
    });
  }

  test('looksLikeTileUrl distinguishes tile endpoints from mbtiles', () {
    expect(HttpVectorTileSource.looksLikeTileUrl('https://x/planet'), isTrue);
    expect(
      HttpVectorTileSource.looksLikeTileUrl('https://x/{z}/{x}/{y}.pbf'),
      isTrue,
    );
    expect(
      HttpVectorTileSource.looksLikeTileUrl('https://x/region.mbtiles'),
      isFalse,
    );
    expect(HttpVectorTileSource.looksLikeTileUrl('/local/x.mbtiles'), isFalse);
  });
}

const _endpoint =
    'https://test-user:test-password@tiles.example/planet?key=test-key';
const _template =
    'https://test-user:test-password@tiles.example/pt/{z}/{x}/{y}.pbf?key=test-key';

http.Response _successResponse(bool tileJson) => tileJson
    ? http.Response(
        jsonEncode({
          'tiles': [_template],
          'minzoom': 5,
          'maxzoom': 14,
        }),
        200,
      )
    : http.Response.bytes([9, 9], 200);

Future<List<int>?> _requestVectorData(
  http.Client client, {
  required bool tileJson,
}) async {
  final source = await HttpVectorTileSource.open(
    tileJson ? _endpoint : _template,
    client: client,
  );
  try {
    return tileJson
        ? [source.minZoom, source.maxZoom]
        : await source.readTile(10, 1, 2);
  } finally {
    await source.close();
  }
}

Matcher _statusFailure(String kind, int status) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'Vector $kind request failed (HTTP $status).',
  ),
);
