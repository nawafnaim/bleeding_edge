// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub.source.hosted;

import 'dart:async';
import 'dart:io' as io;
import "dart:convert";

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../exceptions.dart';
import '../http.dart';
import '../io.dart';
import '../log.dart' as log;
import '../package.dart';
import '../pubspec.dart';
import '../utils.dart';
import 'cached.dart';

/// A package source that gets packages from a package hosting site that uses
/// the same API as pub.dartlang.org.
class HostedSource extends CachedSource {
  final name = "hosted";
  final hasMultipleVersions = true;

  /// Gets the default URL for the package server for hosted dependencies.
  static String get defaultUrl {
    var url = io.Platform.environment["PUB_HOSTED_URL"];
    if (url != null) return url;

    return "https://pub.dartlang.org";
  }

  /// Downloads a list of all versions of a package that are available from the
  /// site.
  Future<List<Version>> getVersions(String name, description) {
    var url =
        _makeUrl(description, (server, package) => "$server/api/packages/$package");

    log.io("Get versions from $url.");
    return httpClient.read(url, headers: PUB_API_HEADERS).then((body) {
      var doc = JSON.decode(body);
      return doc['versions'].map(
          (version) => new Version.parse(version['version'])).toList();
    }).catchError((ex, stackTrace) {
      var parsed = _parseDescription(description);
      _throwFriendlyError(ex, stackTrace, parsed.first, parsed.last);
    });
  }

  /// Downloads and parses the pubspec for a specific version of a package that
  /// is available from the site.
  Future<Pubspec> describeUncached(PackageId id) {
    // Request it from the server.
    var url = _makeVersionUrl(
        id,
        (server, package, version) =>
            "$server/api/packages/$package/versions/$version");

    log.io("Describe package at $url.");
    return httpClient.read(url, headers: PUB_API_HEADERS).then((version) {
      version = JSON.decode(version);

      // TODO(rnystrom): After this is pulled down, we could place it in
      // a secondary cache of just pubspecs. This would let us have a
      // persistent cache for pubspecs for packages that haven't actually
      // been downloaded.
      return new Pubspec.fromMap(
          version['pubspec'],
          systemCache.sources,
          expectedName: id.name,
          location: url);
    }).catchError((ex, stackTrace) {
      var parsed = _parseDescription(id.description);
      _throwFriendlyError(ex, stackTrace, id.name, parsed.last);
    });
  }

  /// Downloads the package identified by [id] to the system cache.
  Future<Package> downloadToSystemCache(PackageId id) {
    return isInSystemCache(id).then((inCache) {
      // Already cached so don't download it.
      if (inCache) return true;

      var packageDir = _getDirectory(id);
      ensureDir(path.dirname(packageDir));
      var parsed = _parseDescription(id.description);
      return _download(parsed.last, parsed.first, id.version, packageDir);
    }).then((found) {
      if (!found) fail('Package $id not found.');
      return new Package.load(id.name, _getDirectory(id), systemCache.sources);
    });
  }

  /// The system cache directory for the hosted source contains subdirectories
  /// for each separate repository URL that's used on the system.
  ///
  /// Each of these subdirectories then contains a subdirectory for each
  /// package downloaded from that site.
  Future<String> getDirectory(PackageId id) =>
      new Future.value(_getDirectory(id));

  String _getDirectory(PackageId id) {
    var parsed = _parseDescription(id.description);
    var dir = _urlToDirectory(parsed.last);
    return path.join(systemCacheRoot, dir, "${parsed.first}-${id.version}");
  }

  String packageName(description) => _parseDescription(description).first;

  bool descriptionsEqual(description1, description2) =>
      _parseDescription(description1) == _parseDescription(description2);

  /// Ensures that [description] is a valid hosted package description.
  ///
  /// There are two valid formats. A plain string refers to a package with the
  /// given name from the default host, while a map with keys "name" and "url"
  /// refers to a package with the given name from the host at the given URL.
  dynamic parseDescription(String containingPath, description,
      {bool fromLockFile: false}) {
    _parseDescription(description);
    return description;
  }

  /// Re-downloads all packages that have been previously downloaded into the
  /// system cache from any server.
  Future<Pair<int, int>> repairCachedPackages() {
    final completer0 = new Completer();
    scheduleMicrotask(() {
      try {
        join0() {
          var successes = 0;
          var failures = 0;
          var it0 = listDir(systemCacheRoot).iterator;
          break0() {
            completer0.complete(new Pair(successes, failures));
          }
          var trampoline0;
          continue0() {
            trampoline0 = null;
            if (it0.moveNext()) {
              var serverDir = it0.current;
              var url = _directoryToUrl(path.basename(serverDir));
              var packages =
                  _getCachedPackagesInDirectory(path.basename(serverDir));
              packages.sort(Package.orderByNameAndVersion);
              var it1 = packages.iterator;
              break1() {
                trampoline0 = continue0;
                do trampoline0(); while (trampoline0 != null);
              }
              var trampoline1;
              continue1() {
                trampoline1 = null;
                if (it1.moveNext()) {
                  var package = it1.current;
                  join1() {
                    trampoline1 = continue1;
                    do trampoline1(); while (trampoline1 != null);
                  }
                  catch0(error, stackTrace) {
                    try {
                      failures++;
                      var message =
                          "Failed to repair ${log.bold(package.name)} " "${package.version}";
                      join2() {
                        log.error("${message}. Error:\n${error}");
                        log.fine(stackTrace);
                        tryDeleteEntry(package.dir);
                        join1();
                      }
                      if (url != defaultUrl) {
                        message += " from ${url}";
                        join2();
                      } else {
                        join2();
                      }
                    } catch (error, stackTrace) {
                      completer0.completeError(error, stackTrace);
                    }
                  }
                  try {
                    new Future.value(
                        _download(url, package.name, package.version, package.dir)).then((x0) {
                      trampoline1 = () {
                        trampoline1 = null;
                        try {
                          x0;
                          successes++;
                          join1();
                        } catch (e0, s0) {
                          catch0(e0, s0);
                        }
                      };
                      do trampoline1(); while (trampoline1 != null);
                    }, onError: catch0);
                  } catch (e1, s1) {
                    catch0(e1, s1);
                  }
                } else {
                  break1();
                }
              }
              trampoline1 = continue1;
              do trampoline1(); while (trampoline1 != null);
            } else {
              break0();
            }
          }
          trampoline0 = continue0;
          do trampoline0(); while (trampoline0 != null);
        }
        if (!dirExists(systemCacheRoot)) {
          completer0.complete(new Pair(0, 0));
        } else {
          join0();
        }
      } catch (e, s) {
        completer0.completeError(e, s);
      }
    });
    return completer0.future;
  }

  /// Gets all of the packages that have been downloaded into the system cache
  /// from the default server.
  List<Package> getCachedPackages() {
    return _getCachedPackagesInDirectory(_urlToDirectory(defaultUrl));
  }

  /// Gets all of the packages that have been downloaded into the system cache
  /// into [dir].
  List<Package> _getCachedPackagesInDirectory(String dir) {
    var cacheDir = path.join(systemCacheRoot, dir);
    if (!dirExists(cacheDir)) return [];

    return listDir(
        cacheDir).map(
            (entry) => new Package.load(null, entry, systemCache.sources)).toList();
  }

  /// Downloads package [package] at [version] from [server], and unpacks it
  /// into [destPath].
  Future<bool> _download(String server, String package, Version version,
      String destPath) {
    return new Future.sync(() {
      var url = Uri.parse("$server/packages/$package/versions/$version.tar.gz");
      log.io("Get package from $url.");
      log.message('Downloading ${log.bold(package)} ${version}...');

      // Download and extract the archive to a temp directory.
      var tempDir = systemCache.createTempDir();
      return httpClient.send(
          new http.Request(
              "GET",
              url)).then((response) => response.stream).then((stream) {
        return timeout(
            extractTarGz(stream, tempDir),
            HTTP_TIMEOUT,
            url,
            'downloading $url');
      }).then((_) {
        // Remove the existing directory if it exists. This will happen if
        // we're forcing a download to repair the cache.
        if (dirExists(destPath)) deleteEntry(destPath);

        // Now that the get has succeeded, move it to the real location in the
        // cache. This ensures that we don't leave half-busted ghost
        // directories in the user's pub cache if a get fails.
        renameDir(tempDir, destPath);
        return true;
      });
    });
  }

  /// When an error occurs trying to read something about [package] from [url],
  /// this tries to translate into a more user friendly error message.
  ///
  /// Always throws an error, either the original one or a better one.
  void _throwFriendlyError(error, StackTrace stackTrace, String package,
      String url) {
    if (error is PubHttpException && error.response.statusCode == 404) {
      throw new PackageNotFoundException(
          "Could not find package $package at $url.",
          error,
          stackTrace);
    }

    if (error is TimeoutException) {
      fail(
          "Timed out trying to find package $package at $url.",
          error,
          stackTrace);
    }

    if (error is io.SocketException) {
      fail(
          "Got socket error trying to find package $package at $url.",
          error,
          stackTrace);
    }

    // Otherwise re-throw the original exception.
    throw error;
  }
}

/// This is the modified hosted source used when pub get or upgrade are run
/// with "--offline".
///
/// This uses the system cache to get the list of available packages and does
/// no network access.
class OfflineHostedSource extends HostedSource {
  /// Gets the list of all versions of [name] that are in the system cache.
  Future<List<Version>> getVersions(String name, description) {
    return newFuture(() {
      var parsed = _parseDescription(description);
      var server = parsed.last;
      log.io(
          "Finding versions of $name in " "$systemCacheRoot/${_urlToDirectory(server)}");
      return _getCachedPackagesInDirectory(
          _urlToDirectory(
              server)).where(
                  (package) => package.name == name).map((package) => package.version).toList();
    }).then((versions) {
      // If there are no versions in the cache, report a clearer error.
      if (versions.isEmpty) fail("Could not find package $name in cache.");

      return versions;
    });
  }

  Future<bool> _download(String server, String package, Version version,
      String destPath) {
    // Since HostedSource is cached, this will only be called for uncached
    // packages.
    throw new UnsupportedError("Cannot download packages when offline.");
  }

  Future<Pubspec> doDescribeUncached(PackageId id) {
    // [getVersions()] will only return packages that are already cached.
    // [CachedSource] will only call [doDescribeUncached()] on a package after
    // it has failed to find it in the cache, so this code should not be
    // reached.
    throw new UnsupportedError("Cannot describe packages when offline.");
  }
}

/// Given a URL, returns a "normalized" string to be used as a directory name
/// for packages downloaded from the server at that URL.
///
/// This normalization strips off the scheme (which is presumed to be HTTP or
/// HTTPS) and *sort of* URL-encodes it. I say "sort of" because it does it
/// incorrectly: it uses the character's *decimal* ASCII value instead of hex.
///
/// This could cause an ambiguity since some characters get encoded as three
/// digits and others two. It's possible for one to be a prefix of the other.
/// In practice, the set of characters that are encoded don't happen to have
/// any collisions, so the encoding is reversible.
///
/// This behavior is a bug, but is being preserved for compatibility.
String _urlToDirectory(String url) {
  // Normalize all loopback URLs to "localhost".
  url = url.replaceAllMapped(
      new RegExp(r"^https?://(127\.0\.0\.1|\[::1\])?"),
      (match) => match[1] == null ? '' : 'localhost');
  return replace(
      url,
      new RegExp(r'[<>:"\\/|?*%]'),
      (match) => '%${match[0].codeUnitAt(0)}');
}

/// Given a directory name in the system cache, returns the URL of the server
/// whose packages it contains.
///
/// See [_urlToDirectory] for details on the mapping. Note that because the
/// directory name does not preserve the scheme, this has to guess at it. It
/// chooses "http" for loopback URLs (mainly to support the pub tests) and
/// "https" for all others.
String _directoryToUrl(String url) {
  // Decode the pseudo-URL-encoded characters.
  var chars = '<>:"\\/|?*%';
  for (var i = 0; i < chars.length; i++) {
    var c = chars.substring(i, i + 1);
    url = url.replaceAll("%${c.codeUnitAt(0)}", c);
  }

  // Figure out the scheme.
  var scheme = "https";

  // See if it's a loopback IP address.
  if (isLoopback(url.replaceAll(new RegExp(":.*"), ""))) scheme = "http";
  return "$scheme://$url";
}

/// Parses [description] into its server and package name components, then
/// converts that to a Uri given [pattern].
///
/// Ensures the package name is properly URL encoded.
Uri _makeUrl(description, String pattern(String server, String package)) {
  var parsed = _parseDescription(description);
  var server = parsed.last;
  var package = Uri.encodeComponent(parsed.first);
  return Uri.parse(pattern(server, package));
}

/// Parses [id] into its server, package name, and version components, then
/// converts that to a Uri given [pattern].
///
/// Ensures the package name is properly URL encoded.
Uri _makeVersionUrl(PackageId id, String pattern(String server, String package,
    String version)) {
  var parsed = _parseDescription(id.description);
  var server = parsed.last;
  var package = Uri.encodeComponent(parsed.first);
  var version = Uri.encodeComponent(id.version.toString());
  return Uri.parse(pattern(server, package, version));
}

/// Parses the description for a package.
///
/// If the package parses correctly, this returns a (name, url) pair. If not,
/// this throws a descriptive FormatException.
Pair<String, String> _parseDescription(description) {
  if (description is String) {
    return new Pair<String, String>(description, HostedSource.defaultUrl);
  }

  if (description is! Map) {
    throw new FormatException("The description must be a package name or map.");
  }

  if (!description.containsKey("name")) {
    throw new FormatException("The description map must contain a 'name' key.");
  }

  var name = description["name"];
  if (name is! String) {
    throw new FormatException("The 'name' key must have a string value.");
  }

  var url = description["url"];
  if (url == null) url = HostedSource.defaultUrl;

  return new Pair<String, String>(name, url);
}
