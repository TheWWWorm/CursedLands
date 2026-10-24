#include <NRD.h>
#include <cstdio>
int main() {
    nrd::DenoiserDesc denoiser{0, nrd::Denoiser::REBLUR_DIFFUSE_SPECULAR};
    nrd::InstanceCreationDesc creation{};
    creation.denoisers = &denoiser; creation.denoisersNum = 1;
    nrd::Instance *instance = nullptr;
    if (nrd::CreateInstance(creation, instance) != nrd::Result::SUCCESS) return 1;
    const auto &desc = *nrd::GetInstanceDesc(*instance);
    for (uint32_t i = 0; i < desc.pipelinesNum; ++i) puts(desc.pipelines[i].shaderIdentifier);
    nrd::DestroyInstance(*instance);
}
