#ifndef _parameters_included_
#define _parameters_included_
extern unsigned int dynamic_num[2];
extern unsigned int static_num[2];
extern const double ramp_time;

void fill_frequency_arrays();
extern double static_freq[2][4096];
extern double destination_freq[2][4096];
extern int dynamic_list[1024];
extern int static_list[16384];
extern const unsigned long long  llSamplerate;
extern const int lThreadsPerBlock;
extern unsigned int tone_count[5];
extern unsigned int dynamic_tone_count[5];
#endif