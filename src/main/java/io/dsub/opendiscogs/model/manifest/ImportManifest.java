package io.dsub.opendiscogs.model.manifest;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Computes the language-neutral OpenDiscogs import manifest v1 fingerprint.
 */
public final class ImportManifest {

  private static final String PREAMBLE = "open-discogs-manifest/v1\n";
  private static final Pattern CHECKSUM_PATTERN = Pattern.compile("^[0-9A-Fa-f]{64}$");
  private static final Set<String> ENTITY_TYPES =
      Set.of("artist", "label", "master", "release");

  private ImportManifest() {
  }

  /**
   * Identifies the content of one dated Discogs entity dump.
   */
  public record Dump(String entityType, LocalDate dumpDate, String checksumSha256) {
  }

  /**
   * Returns the lowercase hexadecimal SHA-256 of the canonical manifest.
   */
  public static String fingerprint(Collection<Dump> dumps) {
    try {
      return HexFormat.of()
          .formatHex(MessageDigest.getInstance("SHA-256").digest(canonical(dumps)));
    } catch (NoSuchAlgorithmException exception) {
      throw new IllegalStateException("SHA-256 is unavailable", exception);
    }
  }

  /**
   * Returns the exact UTF-8 manifest v1 preimage.
   */
  public static byte[] canonical(Collection<Dump> dumps) {
    if (dumps == null || dumps.isEmpty()) {
      throw new IllegalArgumentException("manifest must contain at least one dump");
    }

    List<Dump> normalized = new ArrayList<>(dumps.size());
    Set<String> seen = new HashSet<>();
    for (Dump dump : dumps) {
      if (dump == null || dump.entityType() == null || dump.dumpDate() == null
          || dump.checksumSha256() == null) {
        throw new IllegalArgumentException("manifest dump fields must not be null");
      }
      String entityType = dump.entityType().toLowerCase(Locale.ROOT);
      if (!ENTITY_TYPES.contains(entityType)) {
        throw new IllegalArgumentException("unknown entity type " + dump.entityType());
      }
      if (!seen.add(entityType)) {
        throw new IllegalArgumentException("duplicate entity type " + entityType);
      }
      if (!CHECKSUM_PATTERN.matcher(dump.checksumSha256()).matches()) {
        throw new IllegalArgumentException("invalid SHA-256 for " + entityType);
      }
      normalized.add(
          new Dump(
              entityType,
              dump.dumpDate(),
              dump.checksumSha256().toLowerCase(Locale.ROOT)));
    }
    normalized.sort(Comparator.comparing(Dump::entityType));

    StringBuilder canonical = new StringBuilder(PREAMBLE);
    for (Dump dump : normalized) {
      canonical
          .append(dump.entityType())
          .append('\0')
          .append(dump.dumpDate())
          .append('\0')
          .append(dump.checksumSha256())
          .append('\n');
    }
    return canonical.toString().getBytes(StandardCharsets.UTF_8);
  }
}
