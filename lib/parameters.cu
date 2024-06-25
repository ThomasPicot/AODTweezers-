#include "parameters.h"

// Parameters of the static tweezers
const double center_freq = 103000000.0;
const int N_tweezers_vertical = 4;
const int N_tweezers_horizontal = 4;

// converting frequency with position
const double AOD_2D_freq_to_position = 5.1;
const double tweezers_spacing = 1.559;
double AOD_spacing = tweezers_spacing / AOD_2D_freq_to_position * 1E6;

unsigned int dynamic_num[2] = {0, 0};
unsigned int static_num[2] = {N_tweezers_horizontal, N_tweezers_vertical};
extern const int lThreadsPerBlock = 256;
extern const unsigned long long llSamplerate = 300000000;
extern const double ramp_time = 0.1;
double static_freq[2][4096] = {{}, {}};
double destination_freq[2][4096] = {{}, {}};
unsigned int tone_count[5];
unsigned int dynamic_tone_count[5];

void fill_frequency_arrays()
{
    // Horizontal frequencies (Ch0)
    for (int i = 0; i < N_tweezers_horizontal; ++i)
    {
        double offset = i - N_tweezers_horizontal / 2;
        static_freq[0][i] = center_freq + offset * AOD_spacing;
        destination_freq[0][i] = static_freq[0][i];
    }
    // Vertical frequencies (Ch1)
    for (int i = 0; i < N_tweezers_vertical; ++i)
    {
        double offset = i - N_tweezers_horizontal / 2;
        static_freq[1][i] = center_freq + offset * AOD_spacing;
        destination_freq[1][i] = static_freq[1][i];
    }
}


int dynamic_list[1024] = {0, 5, 6};          // Index of tones that is to be moved
int static_list[16384] = {1, 2, 3, 4, 7, 8}; // Index of tones that is not moved