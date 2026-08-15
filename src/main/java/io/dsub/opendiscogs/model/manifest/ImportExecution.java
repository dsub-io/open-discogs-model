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
  private static final Map<String, Integer> ENTITY_IMPORT_CONTRACT_REVISIONS =
      Map.of("artist", 2, "label", 2, "master", 2, "release", 3);
  private static final Map<String, List<String>> ENTITY_LOCK_DEPENDENCIES =
      Map.of(
          "artist", List.of("artist"),
          "label", List.of("label"),
          "master", List.of("artist", "master"),
          "release", List.of("artist", "label", "master", "release"));

  private ImportExecution() {
  }

  /**
   * Returns the stable second PostgreSQL advisory lock key for an entity type.
   */
  public static int entityLockKey(String entityType) {
    Integer key = ENTITY_LOCK_KEYS.get(normalizeEntityType(entityType));
    if (key == null) {
      throw new IllegalArgumentException("unknown entity type " + entityType);
    }
    return key;
  }

  /**
   * Returns the current stored-data semantics revision for an entity. Successful checkpoints are
   * compatible across processors only at this revision; interrupted runs still require an exact
   * processor name and version match.
   */
  public static int importContractRevision(String entityType) {
    String normalized = normalizeEntityType(entityType);
    Integer revision = ENTITY_IMPORT_CONTRACT_REVISIONS.get(normalized);
    if (revision == null) {
      throw new IllegalArgumentException("unknown entity type: " + entityType);
    }
    return revision;
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
   * Returns every entity lock needed to update the selected entities without racing a referenced
   * entity import.
   */
  public static List<String> requiredLockEntityTypes(Collection<String> selectedEntityTypes) {
    return orderedEntityTypes(selectedEntityTypes).stream()
        .flatMap(entityType -> ENTITY_LOCK_DEPENDENCIES.get(entityType).stream())
        .distinct()
        .sorted()
        .toList();
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

  private static String normalizeEntityType(String entityType) {
    if (entityType == null) {
      throw new IllegalArgumentException("entity type must not be null");
    }
    return entityType.toLowerCase(Locale.ROOT);
  }
}
