package io.dsub.opendiscogs.model.manifest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;

class ImportExecutionTest {

  @Test
  void exposesStableEntityLockOrderAndKeys() {
    assertEquals(
        List.of("artist", "master", "release"),
        ImportExecution.orderedEntityTypes(
            List.of("release", "artist", "master", "artist")));
    assertEquals(1, ImportExecution.entityLockKey("artist"));
    assertEquals(2, ImportExecution.entityLockKey("label"));
    assertEquals(3, ImportExecution.entityLockKey("master"));
    assertEquals(4, ImportExecution.entityLockKey("release"));
    assertThrows(
        IllegalArgumentException.class,
        () -> ImportExecution.entityLockKey("unknown"));
  }

  @Test
  void comparesCandidateAgainstCheckpointDate() {
    LocalDate checkpoint = LocalDate.of(2026, 7, 1);

    assertTrue(ImportExecution.isDowngrade(checkpoint.minusMonths(1), checkpoint));
    assertFalse(ImportExecution.isDowngrade(checkpoint, checkpoint));
    assertFalse(ImportExecution.isDowngrade(checkpoint.plusMonths(1), checkpoint));
  }
}
