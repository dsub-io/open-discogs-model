package io.dsub.opendiscogs.model.manifest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import org.junit.jupiter.api.Test;

class ImportManifestTest {

  @Test
  void fingerprintMatchesSharedConformanceVector() throws IOException {
    String expected = null;
    List<ImportManifest.Dump> dumps = new ArrayList<>();
    try (var input =
            Objects.requireNonNull(
                getClass().getResourceAsStream("/contracts/import-manifest-v1.tsv"));
        var reader =
            new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
      for (String line = reader.readLine(); line != null; line = reader.readLine()) {
        if (line.startsWith("#")) {
          continue;
        }
        String[] fields = line.split("\t");
        if (fields[0].equals("expected_sha256")) {
          expected = fields[1];
        } else {
          dumps.add(
              new ImportManifest.Dump(
                  fields[0], LocalDate.parse(fields[1]), fields[2]));
        }
      }
    }
    Collections.reverse(dumps);

    assertEquals(expected, ImportManifest.fingerprint(dumps));
  }

  @Test
  void rejectsDuplicateTypes() {
    ImportManifest.Dump dump =
        new ImportManifest.Dump(
            "artist", LocalDate.of(2026, 7, 1), "a".repeat(64));

    assertThrows(
        IllegalArgumentException.class,
        () -> ImportManifest.fingerprint(List.of(dump, dump)));
  }

  @Test
  void rejectsMixedDates() {
    assertThrows(
        IllegalArgumentException.class,
        () ->
            ImportManifest.fingerprint(
                List.of(
                    new ImportManifest.Dump(
                        "artist", LocalDate.of(2026, 7, 1), "a".repeat(64)),
                    new ImportManifest.Dump(
                        "label", LocalDate.of(2026, 7, 2), "b".repeat(64)))));
  }
}
