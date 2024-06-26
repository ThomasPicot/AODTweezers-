#ifndef _cudaFunctionscu_included_
#define _cudaFunctionscu_included_
#include "cuda_functions.h"
__device__ __constant__ unsigned int static_num_cuda[4];
__device__ __constant__ int channel_num_cuda;
__device__ __constant__ double llSamplerate_cuda;
__device__ __constant__ double illSamplerate_cuda;
__device__ __constant__ double idynamic_bufferlength_cuda;
__device__ __constant__ size_t static_bufferlength_cuda;
__device__ __constant__ int dynamic_num_cuda[4];
__device__ __constant__ double dynamic_bufferlength_cuda;
__device__ __constant__ double dynamic_loopcount_cuda;
__device__ __constant__ unsigned int tone_count_cuda[5];
__device__ __constant__ unsigned int dynamic_tone_count_cuda[5];
__device__ double istatic_num_cuda[4];
unsigned int dynamic_total = 0;
unsigned int static_total = 0;
bool not_arrived = 1;
const int lNumCh = 4;

const double amplitude_signal = 32767.0 / 4.0;

drv_handle hCard;
size_t static_length;
size_t lBytesPerChannelInNotifySize;
size_t int_temp;
double double_temp;
cudaError_t eCudaErr = cudaSuccess;
short *summed_buffer[4];
short *saved_buffer[4];
short *dynamic_saved_buffer[4];
short **summed_buffer_cuda;
short *final_buffer_cuda;
short **saved_buffer_cuda;
short **dynamic_saved_buffer_cuda;
double *static_buffer_cuda;
double *real_static_freq_cuda;
double real_static_freq[16384];
// ------Dynamics----------------------------
double real_destination_freq[1024];
unsigned int dynamic_buffersize;
double *real_destination_freq_cuda;
int *dynamic_list_cuda;
int *static_list_cuda;
int dynamic_loopcount;

__global__ void tester()
{
}

__global__ void StaticWaveGeneration(double *__restrict__ frequency, double *pnOut, short **sumOut)
{
    size_t i = blockDim.x * blockIdx.x + threadIdx.x;
    for (int ch = 0; ch < channel_num_cuda; ch++)
    {
        double sum = 0.;
        for (size_t j = 0; j < static_num_cuda[ch]; j++)
        {
            int index = tone_count_cuda[ch] + j;
            double phi = __dmul_rn(__dmul_rn(2., istatic_num_cuda[ch]), static_cast<double>(j * j));
            double ampl = __dmul_rn(__dmul_rn(amplitude_signal, sinpi(__fma_rn(__dmul_rn(2.0, frequency[index]), __dmul_rn(static_cast<double>(i), illSamplerate_cuda), phi))), istatic_num_cuda[ch]);
            pnOut[index * static_bufferlength_cuda + i] = ampl;
            sum += ampl;
        }
        sumOut[ch][i] = static_cast<short>(sum);
    }
}

__global__ void StaticWaveGeneration_single(double* restrict frequency, double* pnOut, short** sumOut, float ramp_duration_ms) {
    size_t i = blockDim.x * blockIdx.x + threadIdx.x;
    const float ramp_duration_samples = (ramp_duration_ms / 1000.0) * illSamplerate_cuda; // Conversion en échantillons

    for (int ch = 0; ch < channel_num_cuda; ch++) {
        float sum = 0.;
        for (size_t j = 0; j < static_num_cuda[ch]; j++) {
            int index = tone_count_cuda[ch] + j;
            double phi = __fmul_rn(__fmul_rn(2.0f, istatic_num_cuda[ch]), static_cast<short>(j));
            double ramp_factor = fminf(static_cast<short>(i) / ramp_duration_samples, 1.0f); // Facteur de la rampe entre 0 et 1
            double ramped_amplitude = amplitude_signal * ramp_factor; // Amplitude avec la rampe
            if (ramp_factor == 1.0f) {
                ramped_amplitude = amplitude_signal; // Amplitude maximale après la rampe
            }

            float ampl = __fmul_rn(__fmul_rn(ramped_amplitude, __sinf(__fmaf_rn(__fmul_rn(__fmul_rn(2.0f, M_PIf32), frequency[index]), __fmul_rn(static_cast<float>(i), illSamplerate_cuda), phi))), istatic_num_cuda[ch]);
            pnOut[index * static_bufferlength_cuda + i] = static_cast<double>(ampl);
            sum += ampl;
        }
        sumOut[ch][i] = static_cast<short>(sum);
    }
}





// __global__ void StaticCombine(double*__restrict__ buffer,short**sum_buf){
//     int i = blockDim.x * blockIdx.x + threadIdx.x;

//     for(int buffer_index=0;buffer_index<channel_num_cuda;buffer_index++){
//         double sum = 0.;
//         for (size_t j=0; j<static_num_cuda[buffer_index];j++){
//             sum += buffer[(tone_count_cuda[buffer_index]+j)*static_bufferlength_cuda+i];
//         }
//         sum_buf[buffer_index][i] =static_cast<short> (sum);
//     }
// }

__global__ void StaticMux(short **__restrict__ buffer, short *pnOut)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    for (int j = 0; j < channel_num_cuda; j++)
    {
        pnOut[i * channel_num_cuda + j] = buffer[j][i];
    }
}

__global__ void DynamicMux(unsigned int startPosition, short **__restrict__ buffer, short *pnOut)
{
    size_t i = blockDim.x * blockIdx.x + threadIdx.x;
    for (int j = 0; j < channel_num_cuda; j++)
    {
        pnOut[i * channel_num_cuda + j] = buffer[j][i + startPosition];
    }
}

__global__ void WaveformCopier(short *__restrict__ buffer, short *pnOut)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    pnOut[i] = buffer[i];
}

__global__ void Pre_computer(double *__restrict__ static_buf, int *__restrict__ static_list, double *__restrict__ ddest_freq,
                             int *__restrict__ ddy_list, short *final_buf, short **dynamic_buf, double *__restrict__ dstartFreq)
{
    size_t i = blockDim.x * blockIdx.x + threadIdx.x;
    double dump;
    double sum;
    __shared__ double startFreq[1024];
    __shared__ double dest_freq[1024];
    __shared__ unsigned short dy_list[1024];
    for (int buffer_index = 0; buffer_index < channel_num_cuda; buffer_index++)
    {
        for (int iter = 0; iter <= (dynamic_num_cuda[buffer_index]) / 256 + 1; iter++)
        {
            if (iter * 256 + threadIdx.x < dynamic_num_cuda[buffer_index])
            {
                startFreq[iter * 256 + threadIdx.x] = dstartFreq[ddy_list[dynamic_tone_count_cuda[buffer_index] + iter * 256 + threadIdx.x]];
                dest_freq[iter * 256 + threadIdx.x] = ddest_freq[dynamic_tone_count_cuda[buffer_index] + iter * 256 + threadIdx.x];
                dy_list[iter * 256 + threadIdx.x] = ddy_list[dynamic_tone_count_cuda[buffer_index] + iter * 256 + threadIdx.x];
            }
        }
        __syncthreads();

        sum = 0;
        size_t static_tone_count_start = tone_count_cuda[buffer_index] - dynamic_tone_count_cuda[buffer_index];
        size_t static_tone_count_end = tone_count_cuda[buffer_index + 1] - dynamic_tone_count_cuda[buffer_index + 1];
        if (static_tone_count_end - static_tone_count_start > 0)
        {
            for (int iter = static_tone_count_start; iter < static_tone_count_end; iter++)
            {
                sum += static_buf[static_bufferlength_cuda * static_list[iter] + i];
            }
        }
        double sumf = sum;
        for (int j = 0; j < dynamic_num_cuda[buffer_index]; j++)
        {
            double phi = __fma_rn(dest_freq[j], dynamic_loopcount_cuda * static_cast<double>(static_bufferlength_cuda) - 0.5 * dynamic_bufferlength_cuda, 0.5 * dynamic_bufferlength_cuda * startFreq[j]);
            sumf += amplitude_signal * sinpi(2. * modf(__fma_rn(dest_freq[j], static_cast<double>(i), phi) * illSamplerate_cuda, &dump)) * istatic_num_cuda[buffer_index];
        }
        final_buf[buffer_index + i * channel_num_cuda] = static_cast<short>(sumf);
        if (static_cast<size_t>(dynamic_loopcount_cuda) & 1 == 0)
        {
            double half_buffer_dy = static_cast<double>(static_bufferlength_cuda) * dynamic_loopcount_cuda * 0.5;
            for (int counter = 0; counter < dynamic_loopcount_cuda * 0.5; counter++)
            {
                double position = static_cast<double>(counter * static_bufferlength_cuda + i);
                double k = position + half_buffer_dy;
                float suml = static_cast<float>(sum);
                float sums = static_cast<float>(sum);
                double ratio = position * idynamic_bufferlength_cuda;
                for (int j = 0; j < dynamic_num_cuda[buffer_index]; j++)
                {
                    double startFrequency = startFreq[j];
                    double freqeuncyDiff = dest_freq[j] - startFrequency;
                    double phi = istatic_num_cuda[buffer_index] * static_cast<double>(dy_list[j] * dy_list[j]);
                    double phase_c = position * illSamplerate_cuda * __fma_rn(freqeuncyDiff * ratio * ratio * ratio, (__fma_rn(-3., ratio, __fma_rn(ratio, ratio, 2.5))), startFrequency);
                    double pc = M_PI * 2. * modf(phase_c + phi, &dump);
                    double pc1;
                    if (k < dynamic_bufferlength_cuda)
                    {
                        double ratio1 = k * idynamic_bufferlength_cuda;
                        double phase_c1 = k * illSamplerate_cuda * __fma_rn(freqeuncyDiff * ratio1 * ratio1 * ratio1, (__fma_rn(-3., ratio1, __fma_rn(ratio1, ratio1, 2.5))), startFrequency);
                        pc1 = M_PI * 2. * modf(phase_c1 + phi, &dump);
                    }
                    else
                    {
                        pc1 = M_PI * 2. * modf(__fma_rn((startFrequency + freqeuncyDiff) * static_cast<double>(k - dynamic_bufferlength_cuda), illSamplerate_cuda, __fma_rn(__fma_rn(0.5, freqeuncyDiff, startFrequency) * static_cast<double>(dynamic_bufferlength_cuda), illSamplerate_cuda, phi)), &dump);
                    }
                    half2 temp = __hmul2(__float2half2_rn(amplitude_signal * istatic_num_cuda[buffer_index]), h2sin(__floats2half2_rn(pc, pc1)));
                    sums += __low2float(temp);
                    suml += __high2float(temp);
                }
                dynamic_buf[buffer_index][static_cast<size_t>(position)] = static_cast<short>(sums);
                dynamic_buf[buffer_index][static_cast<size_t>(k)] = static_cast<short>(suml);
            }
        }
        else
        {
            double half_buffer_dy = static_cast<double>(static_bufferlength_cuda) * (dynamic_loopcount_cuda - 1.) * 0.5;
            for (int counter = 0; counter < (size_t)(dynamic_loopcount_cuda) * 0.5; counter++)
            {
                float suml = static_cast<float>(sum);
                float sums = static_cast<float>(sum);
                double position = static_cast<double>(counter * static_bufferlength_cuda + i);
                double k = position + half_buffer_dy;
                double ratio = position * idynamic_bufferlength_cuda;
                for (int j = 0; j < dynamic_num_cuda[buffer_index]; j++)
                {
                    double startFrequency = startFreq[j];
                    double freqeuncyDiff = dest_freq[j] - startFrequency;
                    double phi = istatic_num_cuda[buffer_index] * static_cast<double>(dy_list[j] * dy_list[j]);
                    double phase_c = position * illSamplerate_cuda * __fma_rn(freqeuncyDiff * ratio * ratio * ratio, (__fma_rn(-3., ratio, __fma_rn(ratio, ratio, 2.5))), startFrequency);
                    double pc = M_PI * 2. * modf(phase_c + phi, &dump);
                    double ratio1 = k * idynamic_bufferlength_cuda;
                    double phase_c1 = k * illSamplerate_cuda * __fma_rn(freqeuncyDiff * ratio1 * ratio1 * ratio1, (__fma_rn(-3., ratio1, __fma_rn(ratio1, ratio1, 2.5))), startFrequency);
                    double pc1 = M_PI * 2. * modf(phase_c1 + phi, &dump);
                    half2 temp = __hmul2(__float2half2_rn(amplitude_signal * istatic_num_cuda[buffer_index]), h2sin(__floats2half2_rn(pc, pc1)));
                    sums += __low2float(temp);
                    suml += __high2float(temp);
                }
                dynamic_buf[buffer_index][static_cast<size_t>(position)] = static_cast<short>(sums);
                dynamic_buf[buffer_index][static_cast<size_t>(k)] = static_cast<short>(suml);
            }
            float sums = static_cast<float>(sum);
            double position = static_cast<double>((dynamic_loopcount_cuda - 1) * static_bufferlength_cuda + i);
            for (int j = 0; j < dynamic_num_cuda[buffer_index]; j++)
            {
                double startFrequency = startFreq[j];
                double freqeuncyDiff = dest_freq[j] - startFrequency;
                double phi = istatic_num_cuda[buffer_index] * static_cast<double>(dy_list[j] * dy_list[j]);
                double pc1;
                if (position < dynamic_bufferlength_cuda)
                {
                    double ratio1 = position * idynamic_bufferlength_cuda;
                    double phase_c1 = position * illSamplerate_cuda * __fma_rn(freqeuncyDiff * ratio1 * ratio1 * ratio1, (__fma_rn(-3., ratio1, __fma_rn(ratio1, ratio1, 2.5))), startFrequency);
                    pc1 = M_PI * 2. * modf(phase_c1 + phi, &dump);
                }
                else
                {
                    pc1 = M_PI * 2. * modf(__fma_rn((startFrequency + freqeuncyDiff) * (position - dynamic_bufferlength_cuda), illSamplerate_cuda, __fma_rn(__fma_rn(0.5, freqeuncyDiff, startFrequency) * static_cast<double>(dynamic_bufferlength_cuda), illSamplerate_cuda, phi)), &dump);
                }
                sums += __half2float(__hmul(__double2half(amplitude_signal * istatic_num_cuda[buffer_index]), hsin(__double2half(pc1))));
            }
            dynamic_buf[buffer_index][static_cast<size_t>(position)] = static_cast<short>(sums);
        }
        __syncthreads();
    }
}

void tone_counter(int dynamic)
{
    unsigned int counter = 0;
    tone_count[0] = 0;
    for (int i = 0; i < lNumCh; i++)
    {
        counter += static_num[i];
        tone_count[i + 1] = counter;
    }
    if (dynamic)
    {
        counter = 0;
        dynamic_tone_count[0] = 0;
        for (int i = 0; i < lNumCh; i++)
        {
            counter += dynamic_num[i];
            dynamic_tone_count[i + 1] = counter;
        }
    }
}

int staticBufferMalloc()
{

    eCudaErr = cudaMalloc((void **)&real_static_freq_cuda, static_total * sizeof(double)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating real_static_freq_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpy(real_static_freq_cuda, real_static_freq, static_total * sizeof(double), cudaMemcpyHostToDevice);
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy real_static_freq_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    for (int i = 0; i < lNumCh; i++)
    {
        eCudaErr = cudaMalloc((void **)&summed_buffer[i], lBytesPerChannelInNotifySize); // Configure software buffer
        if (eCudaErr != cudaSuccess)
        {
            printf("Allocating summed_buffer on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
            spcm_vClose(hCard);
            cuda_cleanup();
            return 1;
        }
    }

    double_temp = 1. / llSamplerate;
    eCudaErr = cudaMemcpyToSymbol(illSamplerate_cuda, &double_temp, sizeof(double));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy illSamplerate_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpyToSymbol(tone_count_cuda, tone_count, 5 * sizeof(unsigned int));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy tone_count_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpyToSymbol(static_num_cuda, static_num, sizeof(static_num));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy static_num_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    double double_array_temp[4];
    for (int i = 0; i < 4; i++)
    {
        if (static_num[i])
        {
            double_array_temp[i] = 1. / static_num[i];
        }
        else
        {
            double_array_temp[i] = 0;
        }
    }

    eCudaErr = cudaMemcpyToSymbol(dynamic_tone_count_cuda, &dynamic_tone_count, 5 * sizeof(unsigned int));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy dynamic_tone_count_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpyToSymbol(istatic_num_cuda, double_array_temp, 4 * sizeof(double));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy istatic_num_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMalloc((void **)&static_buffer_cuda, (unsigned long long)4 * static_total * lBytesPerChannelInNotifySize); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating static_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    printf("Malloced size: %llu\n", (unsigned long long)4 * static_total * lBytesPerChannelInNotifySize);
    eCudaErr = cudaMalloc((void **)&summed_buffer_cuda, sizeof(summed_buffer)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating summed_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMemcpy(summed_buffer_cuda, summed_buffer, sizeof(summed_buffer), cudaMemcpyHostToDevice); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy summed_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpyToSymbol(channel_num_cuda, &lNumCh, sizeof(int));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMalloc channel_num_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }

    eCudaErr = cudaMemcpyToSymbol(static_bufferlength_cuda, &static_length, sizeof(static_length));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpyToSymbol static_bufferlength_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    return 0;
}

int dynamicBufferMalloc()
{
    for (int i = 0; i < lNumCh; i++)
    {
        eCudaErr = cudaMalloc((void **)&saved_buffer[i], lBytesPerChannelInNotifySize); // Configure software buffer
        if (eCudaErr != cudaSuccess)
        {
            printf("Allocating saved_buffer on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
            spcm_vClose(hCard);
            cuda_cleanup();
            return 1;
        }

        eCudaErr = cudaMalloc((void **)&dynamic_saved_buffer[i], dynamic_loopcount * lBytesPerChannelInNotifySize); // Configure software buffer
        if (eCudaErr != cudaSuccess)
        {
            printf("Allocating dynamic_saved_buffer on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
            spcm_vClose(hCard);
            cuda_cleanup();
            return 1;
        }
    }
    eCudaErr = cudaMalloc((void **)&real_destination_freq_cuda, dynamic_total * sizeof(double)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating real_destination_freq_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpy(real_destination_freq_cuda, real_destination_freq, dynamic_total * sizeof(double), cudaMemcpyHostToDevice);
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy real_destination_freq_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }

    eCudaErr = cudaMalloc((void **)&dynamic_list_cuda, dynamic_total * sizeof(int)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating dynamic_list_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMalloc((void **)&static_list_cuda, sizeof(static_list)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating dynamic_list_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMalloc((void **)&final_buffer_cuda, lNumCh * lBytesPerChannelInNotifySize); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating final_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMalloc((void **)&saved_buffer_cuda, sizeof(saved_buffer)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating saved_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMalloc((void **)&dynamic_saved_buffer_cuda, sizeof(dynamic_saved_buffer)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("Allocating dynamic_saved_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    eCudaErr = cudaMemcpy(dynamic_list_cuda, dynamic_list, dynamic_total * sizeof(int), cudaMemcpyHostToDevice); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy dynamic_list_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpy(static_list_cuda, static_list, sizeof(static_list), cudaMemcpyHostToDevice); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy static_list_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpy(saved_buffer_cuda, saved_buffer, sizeof(saved_buffer), cudaMemcpyHostToDevice); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy saved_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpy(dynamic_saved_buffer_cuda, dynamic_saved_buffer, sizeof(dynamic_saved_buffer), cudaMemcpyHostToDevice); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy dynamic_saved_buffer_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    double_temp = llSamplerate;
    eCudaErr = cudaMemcpyToSymbol(llSamplerate_cuda, &double_temp, sizeof(double));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpy llSamplerate_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    eCudaErr = cudaMemcpyToSymbol(dynamic_num_cuda, &dynamic_num, sizeof(dynamic_num));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpyToSymbol dynamic_num_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    double dylength = dynamic_buffersize / 2;
    eCudaErr = cudaMemcpyToSymbol(dynamic_bufferlength_cuda, &dylength, sizeof(dylength));
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpyToSymbol dynamic_bufferlength_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return EXIT_FAILURE;
    }
    double_temp = 1. / dylength;
    eCudaErr = cudaMemcpyToSymbol(idynamic_bufferlength_cuda, &double_temp, sizeof(double)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpyToSymbol idynamic_bufferlength_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    double_temp = dynamic_loopcount;
    eCudaErr = cudaMemcpyToSymbol(dynamic_loopcount_cuda, &double_temp, sizeof(double_temp)); // Configure software buffer
    if (eCudaErr != cudaSuccess)
    {
        printf("cudaMemcpyToSymbol dynamic_loopcount_cuda on GPU failed: %s\n", cudaGetErrorString(eCudaErr));
        spcm_vClose(hCard);
        cuda_cleanup();
        return 1;
    }
    return 0;
}
#endif