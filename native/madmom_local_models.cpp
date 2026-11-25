#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <bcrypt.h>

#include "model_files.hpp"

#include <array>
#include <fstream>
#include <stdexcept>
#include <string>

namespace revelation::madmom {

std::filesystem::path require_model(const ModelFile& model, const std::filesystem::path& directory) {
    const auto path = directory / model.path;
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    if (input && input.tellg() == static_cast<std::streamoff>(model.length)) {
        std::vector<unsigned char> bytes(model.length);
        std::array<unsigned char, 32> hash{};
        input.seekg(0);
        if (input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size())) &&
            BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0, bytes.data(), static_cast<ULONG>(bytes.size()),
                       hash.data(), static_cast<ULONG>(hash.size())) >= 0) {
            constexpr char digits[] = "0123456789abcdef";
            std::string digest;
            for (unsigned char byte : hash) {
                digest += digits[byte >> 4];
                digest += digits[byte & 15];
            }
            if (digest == model.sha256) return path;
        }
    }
    throw std::runtime_error("Missing or corrupt madmom model: " + std::string(model.path) +
                             ". Use the Hub model manager to repair it.");
}

void prepare_models(const std::vector<Frontend>&, const std::filesystem::path&, const std::filesystem::path&) {
    // The inference worker calls require_model for every ensemble member before opening it.
}

} // namespace revelation::madmom
