#include <NRD.h>
#include <cstdio>
int main() {
    nrd::DenoiserDesc denoisers[] = {{0, nrd::Denoiser::REBLUR_DIFFUSE_SPECULAR}, {1, nrd::Denoiser::REBLUR_DIFFUSE_SPECULAR_SH}};
    nrd::InstanceCreationDesc creation{};
    creation.denoisers = denoisers; creation.denoisersNum = 2;
    nrd::Instance *instance = nullptr;
    if (nrd::CreateInstance(creation, instance) != nrd::Result::SUCCESS) return 1;
    const auto &desc = *nrd::GetInstanceDesc(*instance);
    for (uint32_t i = 0; i < desc.pipelinesNum; ++i) puts(desc.pipelines[i].shaderIdentifier);
    nrd::DestroyInstance(*instance);
}
