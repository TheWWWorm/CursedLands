// SPDX-License-Identifier: Apache-2.0
// Local Discord IPC only. No networking, credentials, or background threads.
#pragma once
#include <algorithm>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#undef near
#undef far
#elif defined(__linux__) && !defined(__ANDROID__)
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#endif
namespace godot {
class DiscordIpc : public RefCounted {
    GDCLASS(DiscordIpc, RefCounted)
#ifdef _WIN32
    HANDLE handle = INVALID_HANDLE_VALUE;
#elif defined(__linux__) && !defined(__ANDROID__)
    int handle = -1;
#endif
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("open", "path"), &DiscordIpc::open);
        ClassDB::bind_method(D_METHOD("close"), &DiscordIpc::close);
        ClassDB::bind_method(D_METHOD("is_open"), &DiscordIpc::is_open);
        ClassDB::bind_method(D_METHOD("read_bytes"), &DiscordIpc::read_bytes);
        ClassDB::bind_method(D_METHOD("write_bytes", "data"), &DiscordIpc::write_bytes);
    }
public:
    ~DiscordIpc() { close(); }
    bool is_open() const {
#ifdef _WIN32
        return handle != INVALID_HANDLE_VALUE;
#elif defined(__linux__) && !defined(__ANDROID__)
        return handle >= 0;
#else
        return false;
#endif
    }
    void close() {
#ifdef _WIN32
        if (is_open()) CloseHandle(handle);
        handle = INVALID_HANDLE_VALUE;
#elif defined(__linux__) && !defined(__ANDROID__)
        if (is_open()) ::close(handle);
        handle = -1;
#endif
    }
    bool open(const String &path) {
        close();
#ifdef _WIN32
        // NOWAIT prevents a stalled local client from stalling a game frame.
        handle = CreateFileW(reinterpret_cast<const wchar_t *>(path.utf16().get_data()), GENERIC_READ | GENERIC_WRITE,
                             0, nullptr, OPEN_EXISTING, 0, nullptr);
        if (!is_open()) return false;
        DWORD mode = PIPE_READMODE_BYTE | PIPE_NOWAIT;
        if (!SetNamedPipeHandleState(handle, &mode, nullptr, nullptr)) { close(); return false; }
#elif defined(__linux__) && !defined(__ANDROID__)
        const auto name = path.utf8();
        sockaddr_un address{};
        if (name.length() <= 0 || size_t(name.length()) >= sizeof(address.sun_path)) return false;
        address.sun_family = AF_UNIX;
        std::memcpy(address.sun_path, name.get_data(), name.length() + 1);
        handle = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (handle < 0) return false;
        if (::connect(handle, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) { close(); return false; }
#endif
        return is_open();
    }
    PackedByteArray read_bytes() {
        PackedByteArray data;
        if (!is_open()) return data;
        uint8_t bytes[65536];
#ifdef _WIN32
        DWORD available = 0, count = 0;
        if (!PeekNamedPipe(handle, nullptr, 0, nullptr, &available, nullptr)) { close(); return data; }
        if (available == 0) return data;
        if (!ReadFile(handle, bytes, available > sizeof(bytes) ? sizeof(bytes) : available, &count, nullptr)) {
            if (GetLastError() != ERROR_NO_DATA) close();
            return data;
        }
#elif defined(__linux__) && !defined(__ANDROID__)
        const auto count = recv(handle, bytes, sizeof(bytes), 0);
        if (count <= 0) {
            if (count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)) close();
            return data;
        }
#else
        const int count = 0;
#endif
        data.resize(count);
        if (count > 0) std::copy(bytes, bytes + count, data.ptrw());
        return data;
    }
    int64_t write_bytes(const PackedByteArray &data) {
        if (!is_open() || data.size() > 65536) return -1;
        if (data.is_empty()) return 0;
#ifdef _WIN32
        DWORD count = 0;
        if (!WriteFile(handle, data.ptr(), DWORD(data.size()), &count, nullptr)) {
            if (GetLastError() == ERROR_NO_DATA) return 0;
            close(); return -1;
        }
        return count;
#elif defined(__linux__) && !defined(__ANDROID__)
        const auto count = send(handle, data.ptr(), data.size(), MSG_NOSIGNAL);
        if (count < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) return 0;
            close(); return -1;
        }
        return count;
#else
        return -1;
#endif
    }
};
}
