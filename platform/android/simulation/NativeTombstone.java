// SPDX-License-Identifier: Apache-2.0
package org.cursedlands.simulation;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/** Bounded reader for the public debuggerd tombstone protobuf (Android 12+).
 * https://android.googlesource.com/platform/system/core/+/refs/heads/main/debuggerd/proto/tombstone.proto
 * Only the signal, abort/cause text and crashing thread's backtrace are retained.
 * Memory dumps, registers, logcat, open files and other threads are not reported.
 */
final class NativeTombstone {
    static final int MAX_BYTES = 4 * 1024 * 1024;
    private static final int MAX_FRAMES = 64;
    private NativeTombstone() {}

    static String read(InputStream stream, int expectedPid) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = stream.read(buffer, 0, Math.min(buffer.length, MAX_BYTES + 1 - bytes.size()))) != -1) {
            if (count == 0) throw new IOException("empty read");
            bytes.write(buffer, 0, count);
            if (bytes.size() > MAX_BYTES) throw new IOException("trace limit");
        }
        return parse(bytes.toByteArray(), expectedPid);
    }

    static String parse(byte[] data, int expectedPid) throws IOException {
        if (data.length > MAX_BYTES) throw new IOException("trace limit");
        Reader root = new Reader(data, 0, data.length);
        long pid = 0, tid = 0;
        StringBuilder out = new StringBuilder();
        int causes = 0;
        while (root.next()) {
            switch (root.field) {
                case 5: pid = root.number(); break;
                case 6: tid = root.number(); break;
                case 10: out.append(signal(root.message())); break;
                case 14: out.append("abort_message: ").append(root.text(4096)).append('\n'); break;
                case 15:
                    if (causes++ < 8) {
                        Reader cause = root.message();
                        while (cause.next()) {
                            if (cause.field == 1) out.append("cause: ").append(cause.text(2048)).append('\n');
                            else cause.skip();
                        }
                    } else root.skip();
                    break;
                case 22: out.append("page_size: ").append(root.number()).append('\n'); break;
                default: root.skip();
            }
            if (out.length() > 32768) throw new IOException("text limit");
        }
        if (expectedPid <= 0 || pid != expectedPid || tid <= 0) throw new IOException("process mismatch");
        out.insert(0, "pid: " + pid + "\ntid: " + tid + "\n");
        // Protobuf field order is unspecified, so select the thread in a second pass.
        root = new Reader(data, 0, data.length);
        while (root.next()) {
            if (root.field != 16) { root.skip(); continue; }
            Reader entry = root.message(), thread = null;
            long key = 0;
            while (entry.next()) {
                if (entry.field == 1) key = entry.number();
                else if (entry.field == 2) thread = entry.message();
                else entry.skip();
            }
            if (key == tid && thread != null) {
                appendThread(out, thread, tid);
                break;
            }
        }
        return out.toString();
    }

    private static String signal(Reader r) throws IOException {
        long number = 0, code = 0, address = 0;
        boolean hasAddress = false;
        String name = "", codeName = "";
        while (r.next()) {
            switch (r.field) {
                case 1: number = r.number(); break;
                case 2: name = r.text(128); break;
                case 3: code = r.number(); break;
                case 4: codeName = r.text(128); break;
                case 8: hasAddress = r.number() != 0; break;
                case 9: address = r.number(); break;
                default: r.skip();
            }
        }
        return "signal: " + (int) number + " " + name + "\ncode: " + (int) code + " " + codeName + "\n" +
                (hasAddress ? "fault_address: 0x" + Long.toHexString(address) + "\n" : "");
    }

    private static void appendThread(StringBuilder out, Reader r, long expectedTid) throws IOException {
        int frames = 0, notes = 0;
        while (r.next()) {
            switch (r.field) {
                case 1:
                    if (r.number() != expectedTid) throw new IOException("thread mismatch");
                    break;
                case 2: out.append("thread: ").append(r.text(256)).append('\n'); break;
                case 4:
                    if (frames < MAX_FRAMES) {
                        out.append('#').append(frames).append(' ').append(frame(r.message())).append('\n');
                    } else r.skip();
                    frames++;
                    break;
                case 7:
                    if (notes++ < 4) out.append("backtrace_note: ").append(r.text(1024)).append('\n');
                    else r.skip();
                    break;
                default: r.skip();
            }
            if (out.length() > 131072) throw new IOException("text limit");
        }
        if (frames > MAX_FRAMES) out.append("omitted_frames: ").append(frames - MAX_FRAMES).append('\n');
    }

    private static String frame(Reader r) throws IOException {
        long pc = 0, offset = 0, mapOffset = 0;
        String function = "", file = "", build = "";
        while (r.next()) {
            switch (r.field) {
                case 1: pc = r.number(); break;
                case 4: function = r.text(384); break;
                case 5: offset = r.number(); break;
                case 6: file = r.text(512); break;
                case 7: mapOffset = r.number(); break;
                case 8: build = r.text(160); break;
                default: r.skip();
            }
        }
        return "pc " + Long.toHexString(pc) + " " + file +
                (function.isEmpty() ? "" : " (" + function + "+" + Long.toUnsignedString(offset) + ")") +
                (mapOffset == 0 ? "" : " (map_offset 0x" + Long.toHexString(mapOffset) + ")") +
                (build.isEmpty() ? "" : " (BuildId: " + build + ")");
    }

    /** Zero-copy slices; unknown fields skip without allocating or recursing. */
    private static final class Reader {
        final byte[] data;
        final int end;
        int pos, field, wire;
        Reader(byte[] data, int start, int end) { this.data = data; pos = start; this.end = end; }
        boolean next() throws IOException {
            if (pos == end) return false;
            long tag = varint();
            if (tag <= 0 || tag > 0xffffffffL || (tag >>> 3) == 0) throw new IOException("field tag");
            field = (int) (tag >>> 3);
            wire = (int) (tag & 7);
            return true;
        }
        long varint() throws IOException {
            long value = 0;
            for (int shift = 0; shift < 64; shift += 7) {
                if (pos >= end) throw new IOException("truncated varint");
                int b = data[pos++] & 255;
                if (shift == 63 && (b & 254) != 0) throw new IOException("varint overflow");
                value |= (long) (b & 127) << shift;
                if ((b & 128) == 0) return value;
            }
            throw new IOException("varint overflow");
        }
        long number() throws IOException {
            if (wire != 0) throw new IOException("wire type");
            return varint();
        }
        Reader message() throws IOException {
            if (wire != 2) throw new IOException("wire type");
            long size = varint();
            if (size < 0 || size > end - pos) throw new IOException("truncated field");
            Reader child = new Reader(data, pos, pos + (int) size);
            pos = child.end;
            return child;
        }
        String text(int limit) throws IOException {
            Reader value = message();
            return new String(data, value.pos, Math.min(value.end - value.pos, limit), StandardCharsets.UTF_8);
        }
        void skip() throws IOException {
            switch (wire) {
                case 0: varint(); return;
                case 1: advance(8); return;
                case 2: message(); return;
                case 5: advance(4); return;
                default: throw new IOException("wire type");
            }
        }
        void advance(int size) throws IOException {
            if (size > end - pos) throw new IOException("truncated field");
            pos += size;
        }
    }
}
