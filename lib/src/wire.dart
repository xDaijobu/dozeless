// Helpers for reading maps that arrive over the platform channel.

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

DateTime? timeOrNull(Object? epochMs) =>
    epochMs == null ? null : DateTime.fromMillisecondsSinceEpoch((epochMs as num).toInt());

int? intOrNull(Object? value) => (value as num?)?.toInt();

Map<Object?, Object?> asMap(Object? value) =>
    (value as Map?)?.cast<Object?, Object?>() ?? const <Object?, Object?>{};
