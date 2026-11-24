#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <onnxruntime_cxx_api.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
using namespace godot;

constexpr int sample_rate = 22050;
constexpr int fft_size = 1024;
constexpr int bins = fft_size / 2 + 1;
constexpr int bands = 128;
constexpr int hop = 441;
constexpr int frame_ms = 20;
// The portable ONNX graph materializes its attention matrices on CPU.
// Keep a context border while bounding memory for long songs.
constexpr int chunk_size = 600;
constexpr int border = 32;
constexpr float pi = 3.14159265358979323846f;

struct Frontend {
    std::vector<float> mel;
    std::vector<float> onset;
};

Frontend features(const PackedFloat32Array &samples, const PackedFloat32Array &coefficients) {
    const int frames = int(samples.size()) / hop + 1;
    if (coefficients.size() != fft_size + bands * bins) {
        throw std::runtime_error("Incorrect Beat This! frontend coefficients");
    }
    const float *audio = samples.ptr();
    const float *window = coefficients.ptr();
    const float *filters = window + fft_size;
    std::array<int, bands> first_bin{}, last_bin{};
    for (int band = 0; band < bands; ++band) {
        const float *weights = filters + band * bins;
        int first = 0;
        int last = bins;
        while (first < last && weights[first] == 0) ++first;
        while (last > first && weights[last - 1] == 0) --last;
        first_bin[band] = first;
        last_bin[band] = last;
    }
    Frontend result{std::vector<float>(size_t(frames) * bands), std::vector<float>(frames)};
    std::array<std::complex<float>, fft_size> spectrum{};
    std::array<std::complex<float>, fft_size / 2> roots{};
    std::array<int, fft_size> reverse{};
    for (int k = 0; k < fft_size / 2; ++k) {
        roots[k] = std::polar(1.0f, -2 * pi * k / fft_size);
    }
    for (int i = 1; i < fft_size; ++i) {
        reverse[i] = (reverse[i >> 1] >> 1) | ((i & 1) * (fft_size >> 1));
    }
    for (int frame = 0; frame < frames; ++frame) {
        for (int i = 0; i < fft_size; ++i) {
            int index = frame * hop + i - fft_size / 2;
            if (index < 0) index = -index;
            if (index >= samples.size()) index = 2 * (int(samples.size()) - 1) - index;
            spectrum[reverse[i]] = window[i] * audio[index];
        }
        for (int width = 2; width <= fft_size; width *= 2) {
            for (int first = 0; first < fft_size; first += width) {
                for (int k = 0; k < width / 2; ++k) {
                    const auto even = spectrum[first + k];
                    const auto odd = spectrum[first + k + width / 2] * roots[k * fft_size / width];
                    spectrum[first + k] = even + odd;
                    spectrum[first + k + width / 2] = even - odd;
                }
            }
        }
        std::array<float, bins> magnitude{};
        for (int k = 0; k < bins; ++k) {
            magnitude[k] = std::abs(spectrum[k]) / std::sqrt(float(fft_size));
        }
        for (int band = 0; band < bands; ++band) {
            const float *weights = filters + band * bins;
            float sum = 0;
            for (int k = first_bin[band]; k < last_bin[band]; ++k) sum += magnitude[k] * weights[k];
            const size_t pos = size_t(frame) * bands + band;
            result.mel[pos] = std::log1p(1000 * sum);
            if (frame) result.onset[frame] += std::max(0.0f, result.mel[pos] - result.mel[pos - bands]);
        }
    }
    return result;
}

Array tempo_curve(const std::vector<float> &flux) {
    const int frames = int(flux.size());
    std::vector<float> onset(frames);
    for (int i = 1; i + 1 < frames; ++i) {
        onset[i] = (flux[i - 1] + 2 * flux[i] + flux[i + 1]) * 0.25f;
    }
    Array curve;
    constexpr int min_lag = 11;
    constexpr int max_lag = 76;
    constexpr int half_window = 150;
    for (int center = 0; center < frames; center += 25) {
        const int first = std::max(1, center - half_window);
        const int last = std::min(frames - 1, center + half_window);
        std::array<float, 2 * max_lag + 2> correlations{};
        for (int lag = min_lag - 1; lag < int(correlations.size()); ++lag) {
            double dot = 0, left = 0, right = 0;
            for (int i = first + lag; i < last; ++i) {
                const float a = onset[i - lag], b = onset[i];
                dot += a * b;
                left += a * a;
                right += b * b;
            }
            if (left * right > 1e-8) correlations[lag] = float(dot / std::sqrt(left * right));
        }
        int best = min_lag;
        float best_score = -1;
        for (int lag = min_lag; lag <= max_lag; ++lag) {
            if (correlations[lag] < correlations[lag - 1] || correlations[lag] < correlations[lag + 1]) continue;
            const float prior = std::abs(std::log2(3000.0f / (lag * 130.0f)));
            const float score = correlations[lag] + 0.15f * correlations[2 * lag] - 0.17f * prior;
            if (score > best_score) {
                best_score = score;
                best = lag;
            }
        }
        const float peak = correlations[best];
        if (peak <= 0.08f) continue;
        const float a = correlations[best - 1], b = correlations[best + 1];
        const float curvature = a - 2 * peak + b;
        const float delta = std::abs(curvature) > 1e-6f ? std::clamp(0.5f * (a - b) / curvature, -0.5f, 0.5f) : 0;
        Dictionary point;
        point["time_ms"] = center * frame_ms;
        point["bpm"] = std::round(30000.0f / (best + delta)) / 10.0f;
        point["confidence"] = peak;
        curve.push_back(point);
    }
    return curve;
}

float median(std::vector<float> values) {
    if (values.empty()) return 0;
    auto middle = values.begin() + values.size() / 2;
    std::nth_element(values.begin(), middle, values.end());
    return *middle;
}

struct Pulse {
    float bpm = 0;
    float coherence = 0;
    float anchor_ms = 0;
};

bool has_sustained_octave_change(const Array &curve, float pulse) {
    std::array<int, 3> longest{};
    int previous = -1;
    int count = 0;
    for (int i = 0; i < curve.size(); ++i) {
        const Dictionary point = curve[i];
        const float ratio = float(point["bpm"]) / pulse;
        const int octave = std::abs(ratio - 0.5f) < 0.035f ? 0 :
            (std::abs(ratio - 1.0f) < 0.065f ? 1 : (std::abs(ratio - 2) < 0.13f ? 2 : -1));
        count = octave == previous ? count + 1 : 1;
        previous = octave;
        if (octave >= 0) longest[octave] = std::max(longest[octave], count);
    }
    return longest[1] >= 8 && std::max(longest[0], longest[2]) >= 8;
}

Pulse phase_locked_tempo(const std::vector<float> &flux, const Array &curve, const std::vector<float> &beats) {
    constexpr int block_size = 200;
    if (flux.size() < 3 * block_size || curve.is_empty()) return {};
    std::array<int, 151> support{};
    for (int i = 0; i < curve.size(); ++i) {
        const Dictionary point = curve[i];
        const int bin = std::clamp(int(std::round(float(point["bpm"]) / 2)), 0, 150);
        ++support[bin];
    }
    std::vector<float> hints;
    for (int bin = 20; bin < int(support.size()); ++bin) {
        if (support[bin] < std::max(3, int(curve.size() / 14))) continue;
        hints.push_back(float(2 * bin));
    }
    if (beats.size() >= 9) {
        std::vector<float> intervals;
        for (size_t i = 1; i < beats.size(); ++i) intervals.push_back(beats[i] - beats[i - 1]);
        const float period = median(intervals);
        if (period >= 220 && period <= 1500) {
            std::vector<float> spans;
            for (size_t i = 0; i + 8 < beats.size(); ++i) {
                const float span = (beats[i + 8] - beats[i]) / 8;
                if (std::abs(span - period) < period * 0.085f) spans.push_back(span);
            }
            hints.push_back(60000 / (spans.empty() ? period : median(spans)));
        }
    }
    if (hints.empty()) return {};

    std::vector<float> sorted = flux;
    auto high = sorted.begin() + sorted.size() * 9 / 10;
    std::nth_element(sorted.begin(), high, sorted.end());
    const float ceiling = *high > 1e-4f ? *high * 2.5f : 1e6f;
    std::vector<float> weights = flux;
    std::vector<double> block_energy((weights.size() + block_size - 1) / block_size);
    double energy = 0;
    for (size_t i = 0; i < weights.size(); ++i) {
        weights[i] = std::min(weights[i], ceiling);
        block_energy[i / block_size] += weights[i];
        energy += weights[i];
    }
    if (energy <= 0) return {};

    std::vector<Pulse> candidates;
    std::vector<Pulse> competitors;
    std::vector<std::complex<double>> blocks(block_energy.size());
    for (float hint : hints) {
        Pulse best;
        Pulse strongest;
        for (int offset = -14; offset <= 14; ++offset) {
            const float rate = hint + offset * 0.1f;
            const auto advance = std::polar(1.0, -double(2 * pi) * rate / 3000);
            std::complex<double> wave(1, 0);
            std::fill(blocks.begin(), blocks.end(), std::complex<double>{});
            for (size_t i = 0; i < weights.size(); ++i) {
                blocks[i / block_size] += wave * double(weights[i]);
                wave *= advance;
            }
            std::complex<double> sum{};
            for (const auto &block : blocks) sum += block;
            const float coherence = float(std::abs(sum) / energy);
            if (coherence > strongest.coherence) strongest = {rate, coherence, 0};
            if (coherence < 0.016f || coherence <= best.coherence) continue;
            size_t active = 0, aligned = 0;
            const auto phase = std::conj(sum) / std::abs(sum);
            for (size_t i = 0; i < blocks.size(); ++i) {
                if (block_energy[i] < energy / blocks.size() * 0.15) continue;
                ++active;
                const double score = std::real(blocks[i] * phase) / block_energy[i];
                if (score > std::max(0.005f, coherence * 0.24f)) ++aligned;
            }
            if (active < 3 || aligned * 100 < active * 73) continue;
            const float period = 60000 / rate;
            float anchor = float(-std::arg(sum) * period / (2 * pi));
            if (anchor < 0) anchor += period;
            best = {rate, coherence, anchor};
        }
        if (best.bpm > 0) candidates.push_back(best);
        competitors.push_back(strongest);
    }
    std::sort(candidates.begin(), candidates.end(), [](const Pulse &a, const Pulse &b) {
        return a.coherence > b.coherence;
    });
    if (candidates.empty()) return {};
    const Pulse &best = candidates.front();
    if (has_sustained_octave_change(curve, best.bpm)) return {};
    for (const Pulse &other : competitors) {
        const float ratio = other.bpm / best.bpm;
        if (std::abs(ratio - 1) < 0.04f || std::abs(ratio - 2) < 0.05f || std::abs(ratio - 0.5f) < 0.025f) continue;
        if (other.coherence >= 0.04f && other.coherence * 1.42f > best.coherence) return {};
    }
    return best;
}

// Use beat intervals to disambiguate periodic peaks, including half-time and
// syncopated music. Require a coherent pulse before correcting the onset curve.
void reconcile_tempo(Array &curve, const std::vector<float> &beats) {
    if (beats.size() < 9 || curve.is_empty()) return;
    std::vector<float> intervals;
    for (size_t i = 1; i < beats.size(); ++i) intervals.push_back(beats[i] - beats[i - 1]);
    const float period = median(intervals);
    if (period < 220 || period > 1500) return;

    size_t direct = 0;
    size_t consistent = 0;
    std::vector<float> period_estimates;
    for (size_t i = 0; i < intervals.size(); ++i) {
        const float count = std::round(intervals[i] / period);
        if (count < 1 || count > 4 || std::abs(intervals[i] - count * period) > period * 0.12f) continue;
        ++consistent;
        if (count == 1) ++direct;
    }
    if (direct * 100 < intervals.size() * 83 || consistent * 100 < intervals.size() * 92) return;

    // Multi-beat spans average out the model's 20 ms frame quantization.
    for (size_t i = 0; i + 8 < beats.size(); ++i) {
        const float span = (beats[i + 8] - beats[i]) / 8;
        if (std::abs(span - period) < period * 0.065f) period_estimates.push_back(span);
    }
    if (period_estimates.empty()) return;
    const float pulse = 60000 / median(period_estimates);
    if (has_sustained_octave_change(curve, pulse)) return;
    size_t agreeing = 0;
    for (int i = 0; i < curve.size(); ++i) {
        const Dictionary point = curve[i];
        const float ratio = float(point["bpm"]) / pulse;
        for (float harmonic : {0.5f, 2.0f / 3, 1.0f, 1.5f, 2.0f}) {
            if (std::abs(ratio / harmonic - 1) < 0.05f) {
                ++agreeing;
                break;
            }
        }
    }
    if (agreeing * 100 < size_t(curve.size()) * 70) return;
    for (int i = 0; i < curve.size(); ++i) {
        Dictionary point = curve[i];
        point["bpm"] = std::round(pulse * 10) / 10;
    }
}

void resolve_transition_aliases(Array &curve, const std::vector<float> &beats) {
    struct Run { int first, end; float bpm; };
    std::vector<Run> runs;
    for (int i = 0; i < curve.size(); ++i) {
        const Dictionary point = curve[i];
        const float bpm = point["bpm"];
        if (runs.empty() || std::abs(bpm / runs.back().bpm - 1) > 0.045f) {
            runs.push_back({i, i + 1, bpm});
        } else {
            ++runs.back().end;
        }
    }
    for (size_t index = 1; index + 1 < runs.size(); ++index) {
        const Run &before = runs[index - 1], &middle = runs[index], &after = runs[index + 1];
        if (middle.end - middle.first > 7 || before.end - before.first < 6 || after.end - after.first < 6) continue;
        const auto alias = [middle](float bpm) {
            return std::abs(middle.bpm / bpm - 0.5f) < 0.028f || std::abs(middle.bpm / bpm - 2) < 0.09f;
        };
        if (!alias(before.bpm) && !alias(after.bpm)) continue;
        const Dictionary start = curve[middle.first], stop = curve[middle.end - 1];
        const float onset = start["time_ms"], cutoff = float(stop["time_ms"]) + 500.0f;
        const float period = 60000.0f / middle.bpm;
        int confirmed = 0;
        auto first_beat = std::lower_bound(beats.begin(), beats.end(), onset);
        for (auto beat = first_beat; beat != beats.end() && *beat < cutoff; ++beat) {
            if (beat != first_beat && std::abs((*beat - beat[-1]) / period - 1.0f) < 0.14f) ++confirmed;
        }
        if (confirmed >= 2) continue;
        for (int i = middle.first; i < middle.end; ++i) {
            Dictionary point = curve[i];
            point["bpm"] = 2 * i < middle.first + middle.end ? before.bpm : after.bpm;
        }
    }
}

std::vector<float> detect_peaks(const std::vector<float> &logits) {
    std::vector<float> peaks;
    int adjacent_count = 1;
    for (int i = 0; i < int(logits.size()); ++i) {
        if (logits[i] <= 0) continue;
        const auto start = logits.begin() + std::max(0, i - 3);
        const auto end = logits.begin() + std::min(int(logits.size()), i + 4);
        if (*std::max_element(start, end) != logits[i]) continue;
        if (!peaks.empty() && i - peaks.back() <= 1) {
            peaks.back() += (i - peaks.back()) / ++adjacent_count;
        } else {
            peaks.push_back(float(i));
            adjacent_count = 1;
        }
    }
    for (float &peak : peaks) peak *= frame_ms;
    return peaks;
}

PackedFloat32Array packed(const std::vector<float> &values, float duration) {
    PackedFloat32Array result;
    for (float value : values) {
        if (value >= 0 && value < duration) result.push_back(value);
    }
    return result;
}

void infer(Ort::Session &session, const std::vector<float> &mel, std::vector<float> &beat, std::vector<float> &downbeat) {
    const int frames = int(mel.size() / bands);
    const auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    constexpr std::array<const char *, 1> inputs{"spectrogram"};
    constexpr std::array<const char *, 2> outputs{"beat", "downbeat"};
    std::vector<int> starts;
    for (int start = -border; start < frames - border; start += chunk_size - 2 * border) starts.push_back(start);
    if (frames > chunk_size - 2 * border) starts.back() = frames - (chunk_size - border);
    for (auto cursor = starts.rbegin(); cursor != starts.rend(); ++cursor) {
        const int start = *cursor;
        const int length = std::min(chunk_size, frames + border - start);
        std::vector<float> chunk(size_t(length) * bands);
        const int first = std::max(start, 0);
        const int last = std::min(start + length, frames);
        std::copy(mel.begin() + size_t(first) * bands, mel.begin() + size_t(last) * bands,
                  chunk.begin() + size_t(first - start) * bands);
        const std::array<int64_t, 3> shape{1, length, bands};
        auto tensor = Ort::Value::CreateTensor<float>(memory, chunk.data(), chunk.size(), shape.data(), shape.size());
        auto logits = session.Run(Ort::RunOptions{nullptr}, inputs.data(), &tensor, 1, outputs.data(), outputs.size());
        const auto *beat_result = logits[0].GetTensorData<float>();
        const auto *down_result = logits[1].GetTensorData<float>();
        std::copy(beat_result + border, beat_result + length - border, beat.begin() + start + border);
        std::copy(down_result + border, down_result + length - border, downbeat.begin() + start + border);
    }
}

class RevelationRhythm : public RefCounted {
    GDCLASS(RevelationRhythm, RefCounted);
    std::unique_ptr<Ort::Session> session_;

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("load_model", "model"), &RevelationRhythm::load_model);
        ClassDB::bind_method(D_METHOD("analyze", "samples", "coefficients"), &RevelationRhythm::analyze);
    }

public:
    String load_model(const PackedByteArray &model) {
        if (session_) return {};
        if (model.is_empty()) return "Beat This! ONNX model is missing";
        try {
            static Ort::Env environment(ORT_LOGGING_LEVEL_WARNING, "Revelation");
            Ort::SessionOptions options;
            options.SetIntraOpNumThreads(4);
            options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
            options.DisableCpuMemArena();
            session_ = std::make_unique<Ort::Session>(environment, model.ptr(), model.size(), options);
            return {};
        } catch (const std::exception &error) {
            return String::utf8(error.what());
        }
    }

    Dictionary analyze(const PackedFloat32Array &samples, const PackedFloat32Array &coefficients) const {
        Dictionary result;
        if (!session_) {
            result["error"] = "ONNX Runtime session has not been initialized";
            return result;
        }
        if (samples.size() < 2 * sample_rate || samples.size() > 900 * sample_rate) {
            result["error"] = "Audio must be between 2 seconds and 15 minutes";
            return result;
        }
        try {
            auto frontend = features(samples, coefficients);
            const size_t frames = frontend.onset.size();
            std::vector<float> beat_logits(frames, -1000), downbeat_logits(frames, -1000);
            infer(*session_, frontend.mel, beat_logits, downbeat_logits);
            auto beats = detect_peaks(beat_logits);
            auto downbeats = detect_peaks(downbeat_logits);
            if (!beats.empty()) {
                for (float &time : downbeats) {
                    auto next = std::lower_bound(beats.begin(), beats.end(), time);
                    if (next == beats.end()) time = beats.back();
                    else if (next == beats.begin() || *next - time < time - next[-1]) time = *next;
                    else time = next[-1];
                }
                downbeats.erase(std::unique(downbeats.begin(), downbeats.end()), downbeats.end());
            }
            const float duration = samples.size() * (1000.0f / sample_rate);
            result["duration_ms"] = duration;
            result["beats"] = packed(beats, duration);
            result["downbeats"] = packed(downbeats, duration);
            Array curve = tempo_curve(frontend.onset);
            const Pulse steady = phase_locked_tempo(frontend.onset, curve, beats);
            if (steady.bpm > 0) {
                for (int i = 0; i < curve.size(); ++i) {
                    Dictionary point = curve[i];
                    point["bpm"] = std::round(steady.bpm * 10) / 10;
                }
                result["tempo_anchor_ms"] = steady.anchor_ms;
            } else {
                reconcile_tempo(curve, beats);
                resolve_transition_aliases(curve, beats);
            }
            result["tempo_curve"] = curve;
        } catch (const std::exception &error) {
            result["error"] = String::utf8(error.what());
        }
        return result;
    }
};

void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<RevelationRhythm>();
}

void uninitialize(ModuleInitializationLevel) {}
}  // namespace

extern "C" GDExtensionBool GDE_EXPORT revelation_rhythm_init(
    GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize);
    init.register_terminator(uninitialize);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
