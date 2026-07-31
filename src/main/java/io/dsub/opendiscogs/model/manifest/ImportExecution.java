package io.dsub.opendiscogs.model.manifest;

import java.time.LocalDate;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Shared entity-lock and downgrade rules for OpenDiscogs importers.
 */
public final class ImportExecution {

  /**
   * The first key passed to PostgreSQL two-key advisory lock functions.
   */
  public static final int ADVISORY_LOCK_NAMESPACE = 1329876273;

  private static final Map<String, Integer> ENTITY_LOCK_KEYS =
      Map.of("artist", 1, "label", 2, "master", 3, "release", 4);

  private ImportExecution() {
  }

  /**
   * Returns the stable second PostgreSQL advisory lock key for an entity type.
   */
  public static int entityLockKey(String entityType) {
    if (entityType == null) {
      throw new IllegalArgumentException("entity type must not be null");
    }
    Integer key = ENTITY_LOCK_KEYS.get(entityType.toLowerCase(Locale.ROOT));
    if (key == null) {
      throw new IllegalArgumentException("unknown entity type " + entityType);
    }
    return key;
  }

  /**
   * Validates, de-duplicates, and sorts entity types before lock acquisition.
   */
  public static List<String> orderedEntityTypes(Collection<String> entityTypes) {
    if (entityTypes == null) {
      throw new IllegalArgumentException("entity types must not be null");
    }
    LinkedHashSet<String> unique = new LinkedHashSet<>();
    for (String value : entityTypes) {
      String entityType = value == null ? null : value.toLowerCase(Locale.ROOT);
      entityLockKey(entityType);
      unique.add(entityType);
    }
    return unique.stream().sorted().toList();
  }

  /**
   * Returns true when the candidate dump predates the currently applied dump.
   */
  public static boolean isDowngrade(LocalDate candidate, LocalDate checkpoint) {
    if (candidate == null || checkpoint == null) {
      throw new IllegalArgumentException("candidate and checkpoint dates must not be null");
    }
    return candidate.isBefore(checkpoint);
  }
}
