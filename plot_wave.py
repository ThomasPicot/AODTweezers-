import numpy as np
import matplotlib.pyplot as plt

# Paramètres de configuration
center_freq = 103000000.0
N_tweezers_vertical = 2
N_tweezers_horizontal = 2
AOD_2D_freq_to_position = 5.1
tweezers_spacing = 1.559
AOD_spacing = tweezers_spacing / AOD_2D_freq_to_position * 1E6
llSamplerate = 30000000
ramp_time = 50  # [ms]
amplitude_signal = 32767.0 / 4.0

# Initialiser les tableaux de fréquences
static_freq = np.zeros((2, 4096))

# Remplir les tableaux de fréquences
def fill_frequency_arrays():
    for i in range(N_tweezers_horizontal):
        offset = i - N_tweezers_horizontal / 2
        static_freq[0][i] = center_freq + offset * AOD_spacing
    
    for i in range(N_tweezers_vertical):
        offset = i - N_tweezers_vertical / 2
        static_freq[1][i] = center_freq + offset * AOD_spacing

fill_frequency_arrays()

# Générer la somme de sinusoïdes avec rampe
def generate_sum_of_sinusoids_with_ramp(frequencies, ramp_duration_ms, buffer_length, samplerate):
    t = np.arange(buffer_length) / samplerate
    signal_sum = np.zeros(buffer_length)
    
    ramp_duration_samples = int((ramp_duration_ms / 1000.0) * samplerate)
    
    for freq in frequencies:
        ramp_factor = np.minimum(t / (ramp_duration_samples / samplerate), 1.0)
        ramped_amplitude = amplitude_signal * ramp_factor
        signal = ramped_amplitude * np.sin(2.0 * np.pi * freq * t)
        signal_sum += signal

    return t, signal_sum

# Générer la somme de sinusoïdes sans rampe (amplitude constante)
def generate_sum_of_sinusoids_constant_amplitude(frequencies, buffer_length, samplerate):
    t = np.arange(buffer_length) / samplerate
    signal_sum = np.zeros(buffer_length)
    
    for freq in frequencies:
        signal = amplitude_signal * np.sin(2.0 * np.pi * freq * t)
        signal_sum += signal

    return t, signal_sum

# Fonction principale pour générer et tracer les signaux
def main(use_ramp=True):
    # Paramètres pour l'appel de la fonction
    horizontal_freqs = static_freq[0][:N_tweezers_horizontal]
    vertical_freqs = static_freq[1][:N_tweezers_vertical]
    frequencies = np.concatenate((horizontal_freqs, vertical_freqs))
    buffer_length = int(llSamplerate)  # 1 seconde de données à la résolution donnée

    if use_ramp:
        ramp_duration_ms = ramp_time
        time, signal_sum = generate_sum_of_sinusoids_with_ramp(frequencies, ramp_duration_ms, buffer_length, llSamplerate)
        title_suffix = "with Ramp"
    else:
        time, signal_sum = generate_sum_of_sinusoids_constant_amplitude(frequencies, buffer_length, llSamplerate)
        title_suffix = "with Constant Amplitude"
    
    # Effectuer la FFT
    signal_fft = np.fft.fft(signal_sum)
    fft_freq = np.fft.fftfreq(buffer_length, 1 / llSamplerate)

    # Tracer le signal généré
    plt.figure(1)

    plt.plot(time[:2000000], signal_sum[:2000000], label=f'Sum of Sinusoids {title_suffix}')  # Affichage de la première portion pour la clarté
    plt.title(f'Sum of Sinusoids {title_suffix}')
    plt.xlabel('Time (s)')
    plt.ylabel('Amplitude')
    plt.legend()
    plt.grid(True)

    # Tracer le spectre de fréquences
    plt.figure(2)
    plt.plot(fft_freq[:buffer_length // 2], np.abs(signal_fft)[:buffer_length // 2], label='FFT of Signal')
    plt.title('Frequency Spectrum')
    plt.xlabel('Frequency (Hz)')
    plt.ylabel('Magnitude')
    plt.legend()
    plt.grid(True)

    plt.tight_layout()
    plt.show()

# Exécuter la fonction principale avec ou sans rampe
main(use_ramp=True)  # Changez à False pour l'amplitude constante
