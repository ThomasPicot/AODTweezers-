import numpy as np
import matplotlib.pyplot as plt

# Paramètres à définir selon vos besoins
illSamplerate_cuda = 280000000  
channel_num_cuda = 2        # Exemple de valeur, à remplacer par la vôtre
static_num_cuda = [100, 200] # Exemple de valeurs, à remplacer par les vôtres
tone_count_cuda = [0, 0]    # Exemple de valeurs, à remplacer par les vôtres
istatic_num_cuda = [0.1, 0.2] # Exemple de valeurs, à remplacer par les vôtres
static_bufferlength_cuda = 1024 # Exemple de valeur, à remplacer par la vôtre
amplitude_signal = 32767.0/4.0     

def StaticWaveGeneration_single(frequency, ramp_duration_ms):
    ramp_duration_samples = (ramp_duration_ms / 1000.0) * illSamplerate_cuda
    pnOut = np.zeros((len(frequency), static_bufferlength_cuda))
    sumOut = np.zeros((channel_num_cuda, static_bufferlength_cuda))

    for i in range(static_bufferlength_cuda):
        for ch in range(channel_num_cuda):
            sum_val = 0.0
            for j in range(static_num_cuda[ch]):
                index = tone_count_cuda[ch] + j
                phi = 2.0 * istatic_num_cuda[ch] * j
                ramp_factor = min(float(i) / ramp_duration_samples, 1.0)
                ramped_amplitude = amplitude_signal * ramp_factor

                ampl = ramped_amplitude * np.sin(2.0 * np.pi * frequency[index] * i / illSamplerate_cuda + phi) * istatic_num_cuda[ch]
                pnOut[index, i] = ampl
                sum_val += ampl

            sumOut[ch, i] = sum_val

    return pnOut, sumOut

# Exemple d'utilisation
frequency = np.random.rand(1000)
ramp_duration_ms = 25.0

pnOut, sumOut = StaticWaveGeneration_single(frequency, ramp_duration_ms)

# Tracer le signal généré
time = np.arange(static_bufferlength_cuda) / illSamplerate_cuda

plt.figure(1)

# Tracer pnOut
plt.subplot(2, 1, 1)
for index in range(len(frequency)):
    plt.plot(time, pnOut[index], label=f'Tone {index+1}')
plt.title('pnOut Signal')
plt.xlabel('Time (s)')
plt.ylabel('Amplitude')
plt.legend()

# Tracer sumOut
plt.subplot(2, 1, 2)
for ch in range(channel_num_cuda):
    plt.plot(time, sumOut[ch], label=f'Channel {ch+1}')
plt.title('sumOut Signal')
plt.xlabel('Time (s)')
plt.ylabel('Amplitude')
plt.legend()

plt.tight_layout()
plt.show()
