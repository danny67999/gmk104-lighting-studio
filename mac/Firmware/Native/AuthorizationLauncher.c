#include "AuthorizationLauncher.h"

// The unsigned beta cannot register an SMAppService daemon with a stable
// Apple-issued signing identity. Use the public, one-shot Authorization Services
// C API until that signing identity is available; no permanent helper is installed.
// Swift excludes pre-10.9 deprecated APIs, so keep this compatibility call in C.
OSStatus GMKRunAuthorizedTool(AuthorizationRef authorization,
                             const char *executable,
                             char * const *arguments,
                             FILE **pipe) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return AuthorizationExecuteWithPrivileges(authorization, executable,
                                              kAuthorizationFlagDefaults,
                                              arguments, pipe);
#pragma clang diagnostic pop
}
