package io.dsub.opendiscogs.model.manifest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;

class NonReleaseRelationIdentityVectorsTest {

  private static final String VECTOR_RESOURCE =
      "/contracts/non-release-relation-identity-v1.tsv";
  private static final String IDENTITY_PREFIX =
      "open-discogs/non-release-relation-identity/v1";
  private static final String SLOT_PREFIX =
      "open-discogs/non-release-relation-slot/v1";
  private static final String NULL_VALUE = "null";
  private static final String UNUSED_VALUE = "-";
  private static final String HEX_PREFIX = "hex:";
  private static final int VECTOR_COLUMN_COUNT = 10;
  private static final List<String> EXPECTED_HEADER =
      List.of(
          "kind",
          "id",
          "relation",
          "field_1",
          "field_2",
          "field_3",
          "identity_sha256",
          "attempt",
          "slot",
          "legacy_java_hash");
  private static final Map<String, Integer> FIELD_COUNTS =
      Map.of(
          "artist_name_variation", 1,
          "artist_url", 1,
          "label_url", 1,
          "master_video", 3);

  @Test
  void validatesSharedGoldenVectors() throws IOException, NoSuchAlgorithmException {
    List<GoldenVector> vectors = readVectors();
    Set<String> digestRelations = new HashSet<>();
    Map<Integer, Set<String>> identitiesByLegacyHash = new HashMap<>();
    for (GoldenVector vector : vectors) {
      switch (vector.kind()) {
        case "digest" -> {
          digestRelations.add(vector.relation());
          assertDigest(vector);
          if (!UNUSED_VALUE.equals(vector.legacyJavaHash())) {
            int expectedHash = Integer.parseInt(vector.legacyJavaHash());
            assertEquals(expectedHash, decodeValue(vector.id(), vector.fields().getFirst()).hashCode());
            identitiesByLegacyHash
                .computeIfAbsent(expectedHash, ignored -> new HashSet<>())
                .add(vector.identitySha256());
          }
        }
        case "slot" -> assertSlot(vector);
        default -> throw new IllegalArgumentException(
            "unknown vector kind " + vector.kind() + " for " + vector.id());
      }
    }
    assertEquals(FIELD_COUNTS.keySet(), digestRelations);
    assertEquals(2, identitiesByLegacyHash.get(2112).size());
  }

  private static List<GoldenVector> readVectors() throws IOException {
    InputStream input =
        NonReleaseRelationIdentityVectorsTest.class.getResourceAsStream(VECTOR_RESOURCE);
    assertNotNull(input, "missing " + VECTOR_RESOURCE);
    try (input;
        BufferedReader reader =
            new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
      String header = reader.readLine();
      assertNotNull(header, "empty " + VECTOR_RESOURCE);
      assertEquals(EXPECTED_HEADER, Arrays.asList(header.split("\\t", -1)));
      List<GoldenVector> vectors = new ArrayList<>();
      String line;
      while ((line = reader.readLine()) != null) {
        String[] columns = line.split("\\t", -1);
        if (columns.length != VECTOR_COLUMN_COUNT) {
          throw new IllegalArgumentException(
              "vector column count = " + columns.length + ", want " + VECTOR_COLUMN_COUNT);
        }
        vectors.add(
            new GoldenVector(
                columns[0],
                columns[1],
                columns[2],
                List.of(columns[3], columns[4], columns[5]),
                columns[6],
                columns[7],
                columns[8],
                columns[9]));
      }
      return List.copyOf(vectors);
    }
  }

  private static void assertDigest(GoldenVector vector)
      throws NoSuchAlgorithmException, IOException {
    Integer fieldCount = FIELD_COUNTS.get(vector.relation());
    if (fieldCount == null) {
      throw new IllegalArgumentException("unknown relation " + vector.relation());
    }
    ByteArrayOutputStream preimage = new ByteArrayOutputStream();
    writePrefix(preimage, IDENTITY_PREFIX, vector.relation());
    for (int index = 0; index < vector.fields().size(); index++) {
      String encoded = vector.fields().get(index);
      if (index >= fieldCount) {
        assertEquals(UNUSED_VALUE, encoded, vector.id() + " field " + (index + 1));
        continue;
      }
      String value = trimIdentityValue(decodeValue(vector.id(), encoded));
      if (value == null) {
        preimage.write(0);
      } else {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        preimage.write(1);
        preimage.write(ByteBuffer.allocate(Integer.BYTES).putInt(bytes.length).array());
        preimage.write(bytes);
      }
    }
    String actual =
        HexFormat.of().formatHex(
            MessageDigest.getInstance("SHA-256").digest(preimage.toByteArray()));
    assertEquals(vector.identitySha256(), actual, vector.id());
  }

  private static void assertSlot(GoldenVector vector)
      throws NoSuchAlgorithmException, IOException {
    byte[] digest = HexFormat.of().parseHex(vector.identitySha256());
    assertEquals(32, digest.length, vector.id());
    int attempt = Integer.parseUnsignedInt(vector.attempt());
    ByteArrayOutputStream preimage = new ByteArrayOutputStream();
    writePrefix(preimage, SLOT_PREFIX, vector.relation());
    preimage.write(digest);
    preimage.write(ByteBuffer.allocate(Integer.BYTES).putInt(attempt).array());
    byte[] slotDigest = MessageDigest.getInstance("SHA-256").digest(preimage.toByteArray());
    int actual = ByteBuffer.wrap(slotDigest, 0, Integer.BYTES).getInt();
    assertEquals(Integer.parseInt(vector.slot()), actual, vector.id());
  }

  private static void writePrefix(
      ByteArrayOutputStream output,
      String prefix,
      String relation) throws IOException {
    output.write(prefix.getBytes(StandardCharsets.UTF_8));
    output.write(0);
    output.write(relation.getBytes(StandardCharsets.US_ASCII));
    output.write(0);
  }

  private static String decodeValue(String id, String encoded) {
    if (NULL_VALUE.equals(encoded)) {
      return null;
    }
    if (!encoded.startsWith(HEX_PREFIX)) {
      throw new IllegalArgumentException(
          "vector " + id + " value is not null or hex: " + encoded);
    }
    byte[] bytes = HexFormat.of().parseHex(encoded.substring(HEX_PREFIX.length()));
    return StandardCharsets.UTF_8.decode(ByteBuffer.wrap(bytes)).toString();
  }

  private static String trimIdentityValue(String value) {
    if (value == null) {
      return null;
    }
    int start = 0;
    int end = value.length();
    while (start < end) {
      int codePoint = value.codePointAt(start);
      if (!isIdentityWhitespace(codePoint)) {
        break;
      }
      start += Character.charCount(codePoint);
    }
    while (end > start) {
      int codePoint = value.codePointBefore(end);
      if (!isIdentityWhitespace(codePoint)) {
        break;
      }
      end -= Character.charCount(codePoint);
    }
    return start == end ? null : value.substring(start, end);
  }

  private static boolean isIdentityWhitespace(int value) {
    return value >= 0x0009 && value <= 0x000d
        || value == 0x0020
        || value == 0x0085
        || value == 0x00a0
        || value == 0x1680
        || value >= 0x2000 && value <= 0x200a
        || value == 0x2028
        || value == 0x2029
        || value == 0x202f
        || value == 0x205f
        || value == 0x3000;
  }

  private record GoldenVector(
      String kind,
      String id,
      String relation,
      List<String> fields,
      String identitySha256,
      String attempt,
      String slot,
      String legacyJavaHash) {
  }
}
