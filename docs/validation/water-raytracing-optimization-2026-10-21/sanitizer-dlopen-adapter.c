#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
// Test-only: let ASan interpose calls from this private runtime's extensions.
// The published/custom engine and libraries are not patched.
void *dlopen(const char *file, int flags) {
    static void *(*next_dlopen)(const char *, int);
    if (!next_dlopen) next_dlopen = dlsym(RTLD_NEXT, "dlopen");
    if (file && (strncmp(file, "./src/native/bin/", 17) == 0 ||
                 strstr(file, "/water-raytracing-20261021/native-rt-sanitizers/src/native/bin/")))
        flags &= ~RTLD_DEEPBIND;
    return next_dlopen(file, flags);
}
