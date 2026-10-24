// MinGW's C math headers don't put floating-point abs overloads in the global
// namespace used by MathLib's shared C++/HLSL header. Preserve those overloads.
#include <cmath>
using std::abs;
