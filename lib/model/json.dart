/// A decoded JSON object.
typedef Json = Map<String, Object?>;

/// Reads an optional JSON array of strings; null reads as empty.
List<String> stringList(Object? value) => value == null
    ? const []
    : [for (final v in value as List<Object?>) v! as String];

/// Reads a required JSON array of objects through [parse].
List<T> objectList<T>(Object? value, T Function(Json) parse) => [
  for (final v in value! as List<Object?>) parse(v! as Json),
];
