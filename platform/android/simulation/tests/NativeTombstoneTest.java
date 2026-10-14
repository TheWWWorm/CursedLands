// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Random;

/** Standalone JVM tests; no Android runtime or additional libraries required. */
public final class NativeTombstoneTest {
    private static int checks;
    private static void check(boolean ok, String label) {
        checks++;
        if (!ok) throw new AssertionError(label);
    }
    private static byte[] join(byte[]... parts) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (byte[] part : parts) out.write(part, 0, part.length);
        return out.toByteArray();
    }
    private static byte[] varint(long n) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        while ((n & ~127L) != 0) { out.write((int) (n & 127) | 128); n >>>= 7; }
        out.write((int) n);
        return out.toByteArray();
    }
    private static byte[] number(int field, long n) { return join(varint(field << 3), varint(n)); }
    private static byte[] message(int field, byte[] value) { return join(varint((field << 3) | 2), varint(value.length), value); }
    private static byte[] text(int field, String value) { return message(field, value.getBytes(StandardCharsets.UTF_8)); }
    private static byte[] entry(int tid, String name, byte[] frames) {
        // Deliberately put the map value before its key.
        return message(16, join(message(2, join(number(1, tid), text(2, name), frames)), number(1, tid)));
    }
    private static byte[] fixture(byte[] frames) {
        return join(entry(99, "unrelated worker", message(4, text(6, "unrelated.so"))),
                entry(42, "GLThread", frames), number(6, 42), number(5, 1234),
                message(10, join(number(1, 11), text(2, "SIGSEGV"), number(3, -6),
                    text(4, "SI_TKILL"), number(8, 1))), // fault address zero omitted by proto3
                text(14, "abort fixture"), message(15, text(1, "cause fixture")), number(22, 16384));
    }
    private static void rejects(byte[] bytes, int pid, String label) throws IOException {
        try { NativeTombstone.parse(bytes, pid); }
        catch (IOException expected) { check(true, label); return; }
        check(false, label);
    }
    public static void main(String[] args) throws Exception {
        byte[] frame = message(4, join(number(1, 0x12345678), text(4, "driver_function"), number(5, 7),
                text(6, "/vendor/lib64/egl/libGLESv2_adreno.so"), number(7, 4096), text(8, "aabbcc")));
        byte[] valid = fixture(frame);
        String parsed = NativeTombstone.read(new ByteArrayInputStream(valid), 1234);
        check(parsed.contains("signal: 11 SIGSEGV"), "signal");
        check(parsed.contains("code: -6 SI_TKILL"), "signed int32");
        check(parsed.contains("fault_address: 0x0"), "proto3 omitted zero address");
        check(parsed.contains("thread: GLThread"), "select crash thread, unordered fields");
        check(parsed.contains("#0 pc 12345678 /vendor/lib64/egl/libGLESv2_adreno.so (driver_function+7) (map_offset 0x1000) (BuildId: aabbcc)"), "symbolication data");
        check(!parsed.contains("unrelated"), "other threads excluded");
        check(parsed.contains("abort fixture") && parsed.contains("cause fixture"), "failure details");
        check(parsed.contains("page_size: 16384"), "page size");
        byte[] unknown = join(number(1000, 123), message(1001, new byte[1024]),
                varint((1002 << 3) | 1), new byte[8], varint((1003 << 3) | 5), new byte[4]);
        check(parsed.equals(NativeTombstone.parse(join(unknown, valid), 1234)), "unknown wire types skipped");
        rejects(valid, 1235, "reject foreign process");
        rejects(valid, 0, "reject invalid expected PID");
        rejects(new byte[0], 1234, "empty trace");
        rejects(new byte[] {0}, 1234, "zero tag");
        rejects(new byte[] {8, (byte) 128}, 1234, "truncated varint");
        rejects(join(new byte[] {8}, new byte[] {-1, -1, -1, -1, -1, -1, -1, -1, -1, 2}), 1234, "overflowing varint");
        rejects(join(varint(82), varint(Long.MAX_VALUE)), 1234, "oversized length");
        rejects(join(varint(82), varint(-1)), 1234, "negative length");
        rejects(new byte[] {82, 4, 0}, 1234, "truncated message");
        rejects(join(valid, new byte[] {11}), 1234, "unsupported group wire type");
        rejects(join(valid, new byte[] {9, 0}), 1234, "truncated fixed64");
        rejects(join(number(5, 1234), number(6, 42), message(16, join(number(1, 42), message(2, number(1, 43))))), 1234, "inconsistent thread rejected");
        byte[][] many = new byte[70][];
        Arrays.fill(many, frame);
        String bounded = NativeTombstone.parse(fixture(join(many)), 1234);
        check(bounded.contains("#63 pc") && !bounded.contains("#64 pc") && bounded.contains("omitted_frames: 6"), "bounded backtrace");
        String strings = NativeTombstone.parse(fixture(message(4, text(6, "x".repeat(100000)))), 1234);
        check(strings.length() < 2048, "bounded individual strings");
        try { NativeTombstone.read(new ByteArrayInputStream(new byte[NativeTombstone.MAX_BYTES + 1]), 1234); check(false, "oversized stream"); }
        catch (IOException expected) { check(true, "oversized stream"); }
        for (int size = 0; size < valid.length; size++) {
            // Partial protobufs must never escape with array errors or loop indefinitely.
            try { NativeTombstone.parse(Arrays.copyOf(valid, size), 1234); }
            catch (IOException expected) {}
            checks++;
        }
        Random random = new Random(0x434c);
        for (int i = 0; i < 2000; i++) {
            byte[] bytes = new byte[random.nextInt(512)];
            random.nextBytes(bytes);
            try { NativeTombstone.parse(bytes, 1234); }
            catch (IOException expected) {}
            checks++;
        }
        System.out.println("NativeTombstone: " + checks + " checks passed");
    }
}
