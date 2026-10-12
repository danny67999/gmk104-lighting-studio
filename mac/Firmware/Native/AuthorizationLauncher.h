#include <Security/Authorization.h>
#include <stdio.h>

OSStatus GMKRunAuthorizedTool(AuthorizationRef _Nonnull authorization,
                             const char * _Nonnull executable,
                             char * _Nullable const * _Nonnull arguments,
                             FILE * _Nullable * _Nonnull pipe);
