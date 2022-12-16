#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include <cuda_runtime.h>

#ifdef _MSC_VER
#include <windows.h>
#include <WinCon.h>
#endif

#include <random>

#define CONSOLE_RED "\x1b[91m"
#define CONSOLE_GREEN "\x1b[92m"
#define CONSOLE_YELLOW "\x1b[93m"
#define CONSOLE_RESET "\x1b[39m"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "external/stb_image_write.h"

#include "main.h"
#include "config.h"
#include "common.h"
#include "cpu.h"
#include "openmp.h"
#include "cuda.cuh"
#include "helper.h"

int main(int argc, char **argv)
{
#ifdef _MSC_VER
    {
        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD consoleMode;
        GetConsoleMode(hConsole, &consoleMode);
        consoleMode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;  // Enable support for ANSI colours (Windows 10+)
        SetConsoleMode(hConsole, consoleMode);
    }
#endif
    // Parse args
    Config config;
    parse_args(argc, argv, &config);

    // Load input config
    InputFile user_config;
    {
        //user_cimage.data = stbi_load(config.input_file, &user_cimage.width, &user_cimage.height, &user_cimage.channels, 0);
        //if (!user_cimage.data) {
        //    printf("Unable to load image '%s', please try a different file.\n", config.input_file);
        //    return EXIT_FAILURE;
        //}
        //if (user_cimage.channels == 2) {
        //    printf("2 channel images are not supported, please try a different file.\n");
        //    return EXIT_FAILURE;
        //}
    }

    // Generate Initial Particles from user_config
    const unsigned int particles_count = user_config.circle_count + user_config.square_count;
    Particle* particles = (Particle *)malloc(particles_count * sizeof(Particle));
    {
        // Random engine with a fixed seed and several distributions to be used
        std::mt19937 rng(12);
        std::uniform_real_distribution<float> normalised_float_dist(0, 1);
        std::normal_distribution<float> circle_rad_dist(user_config.circle_rad_average, user_config.circle_rad_standarddev);
        std::normal_distribution<float> circle_opacity_dist(user_config.circle_rad_average, user_config.circle_rad_standarddev);
        std::normal_distribution<float> square_rad_dist(user_config.square_rad_average, user_config.square_rad_standarddev);
        std::normal_distribution<float> square_opacity_dist(user_config.square_rad_average, user_config.square_rad_standarddev);
        std::uniform_int_distribution<int> color_palette_dist(0, sizeof(base_color_palette)/sizeof(unsigned char[3]) - 1);
        // Common
        for (unsigned int i = user_config.circle_count; i < particles_count; ++i) {
            const int palette_index = color_palette_dist(rng);
            particles[i].color[0] = base_color_palette[palette_index][0];
            particles[i].color[1] = base_color_palette[palette_index][1];
            particles[i].color[2] = base_color_palette[palette_index][2];
            particles[i].location[0] = normalised_float_dist(rng) * OUT_IMAGE_WIDTH;
            particles[i].location[1] = normalised_float_dist(rng) * OUT_IMAGE_HEIGHT;
            particles[i].location[2] = normalised_float_dist(rng);
            // particles[i].direction[0]
            // particles[i].direction[1]
            // particles[i].speed
        }
        // Circles
        for (unsigned int i = 0; i < user_config.circle_count; ++i) {
            particles[i].type = Circle;
            particles[i].radius = circle_rad_dist(rng);
            particles[i].opacity = circle_opacity_dist(rng);
        }
        // Squares
        for (unsigned int i = user_config.circle_count; i < particles_count; ++i) {
            particles[i].type = Square;
            particles[i].radius = square_rad_dist(rng);
            particles[i].opacity = square_opacity_dist(rng);
        }
        // Clamp radius/opacity to bounds (use OpenMP in an attempt to trigger OpenMPs hidden init cost)
#pragma omp parallel for 
        for (unsigned int i = user_config.circle_count; i < particles_count; ++i) {
            particles[i].radius = particles[i].radius < MIN_RADIUS ? MIN_RADIUS : particles[i].radius;
            particles[i].radius = particles[i].radius > MAX_RADIUS ? MAX_RADIUS : particles[i].radius;
            particles[i].opacity = particles[i].opacity < MIN_OPACITY ? MIN_OPACITY : particles[i].opacity;
            particles[i].opacity = particles[i].opacity > MAX_OPACITY ? MAX_OPACITY : particles[i].opacity;
        }
    }

    // Create result for validation
    CImage validation_image;
    {
        // @TODO
    }
       
    CImage output_image;
    Runtimes timing_log;
    const int TOTAL_RUNS = config.benchmark ? BENCHMARK_RUNS : 1;
    {
        //Init for run  
        cudaEvent_t startT, initT, stage1T, stage2T, stage3T, stopT;
        CUDA_CALL(cudaEventCreate(&startT));
        CUDA_CALL(cudaEventCreate(&initT));
        CUDA_CALL(cudaEventCreate(&stage1T));
        CUDA_CALL(cudaEventCreate(&stage2T));
        CUDA_CALL(cudaEventCreate(&stage3T));
        CUDA_CALL(cudaEventCreate(&stopT));

        // Run 1 or many times
        memset(&timing_log, 0, sizeof(Runtimes));
        for (int runs = 0; runs < TOTAL_RUNS; ++runs) {
            if (TOTAL_RUNS > 1)
                printf("\r%d/%d", runs + 1, TOTAL_RUNS);
            memset(&output_image, 0, sizeof(CImage));
            output_image.data = (unsigned char*)malloc(OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT * sizeof(unsigned char));
            memset(output_image.data, 0, OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT * sizeof(unsigned char));
            // Run Adaptive Histogram algorithm
            CUDA_CALL(cudaEventRecord(startT));
            CUDA_CALL(cudaEventSynchronize(startT));
            switch (config.mode) {
            case CPU:
                {
                    cpu_begin(particles, particles_count);
                    CUDA_CALL(cudaEventRecord(initT));
                    CUDA_CALL(cudaEventSynchronize(initT));
                    cpu_stage1();
                    CUDA_CALL(cudaEventRecord(stage1T));
                    CUDA_CALL(cudaEventSynchronize(stage1T));
                    cpu_stage2();
                    CUDA_CALL(cudaEventRecord(stage2T));
                    CUDA_CALL(cudaEventSynchronize(stage2T));
                    cpu_stage3();
                    CUDA_CALL(cudaEventRecord(stage3T));
                    CUDA_CALL(cudaEventSynchronize(stage3T));
                    cpu_end(&output_image);
                }
                break;
            case OPENMP:
                {
                    openmp_begin(particles, particles_count);
                    CUDA_CALL(cudaEventRecord(initT));
                    CUDA_CALL(cudaEventSynchronize(initT));
                    openmp_stage1();
                    CUDA_CALL(cudaEventRecord(stage1T));
                    CUDA_CALL(cudaEventSynchronize(stage1T));
                    openmp_stage2();
                    CUDA_CALL(cudaEventRecord(stage2T));
                    CUDA_CALL(cudaEventSynchronize(stage2T));
                    openmp_stage3();
                    CUDA_CALL(cudaEventRecord(stage3T));
                    CUDA_CALL(cudaEventSynchronize(stage3T));
                    openmp_end(&output_image);
                }
                break;
            case CUDA:
                {
                    cuda_begin(particles, particles_count);
                    CUDA_CHECK();
                    CUDA_CALL(cudaEventRecord(initT));
                    CUDA_CALL(cudaEventSynchronize(initT));
                    cuda_stage1();
                    CUDA_CHECK();
                    CUDA_CALL(cudaEventRecord(stage1T));
                    CUDA_CALL(cudaEventSynchronize(stage1T));
                    cuda_stage2();
                    CUDA_CHECK();
                    CUDA_CALL(cudaEventRecord(stage2T));
                    CUDA_CALL(cudaEventSynchronize(stage2T));
                    cuda_stage3();
                    CUDA_CHECK();
                    CUDA_CALL(cudaEventRecord(stage3T));
                    CUDA_CALL(cudaEventSynchronize(stage3T));
                    cuda_end(&output_image);
                }
                break;
            }
            CUDA_CALL(cudaEventRecord(stopT));
            CUDA_CALL(cudaEventSynchronize(stopT));
            // Sum timing info
            float milliseconds = 0;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, startT, initT));
            timing_log.init += milliseconds;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, initT, stage1T));
            timing_log.stage1 += milliseconds;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, stage1T, stage2T));
            timing_log.stage2 += milliseconds;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, stage2T, stage3T));
            timing_log.stage3 += milliseconds;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, stage3T, stopT));
            timing_log.cleanup += milliseconds;
            CUDA_CALL(cudaEventElapsedTime(&milliseconds, startT, stopT));
            timing_log.total += milliseconds;
            // Avoid memory leak
            if (runs + 1 < TOTAL_RUNS) {
                if (output_image.data)
                    free(output_image.data);
            }
        }
        // Convert timing info to average
        timing_log.init /= TOTAL_RUNS;
        timing_log.stage1 /= TOTAL_RUNS;
        timing_log.stage2 /= TOTAL_RUNS;
        timing_log.stage3 /= TOTAL_RUNS;
        timing_log.cleanup /= TOTAL_RUNS;
        timing_log.total /= TOTAL_RUNS;

        // Cleanup timing
        cudaEventDestroy(startT);
        cudaEventDestroy(initT);
        cudaEventDestroy(stage1T);
        cudaEventDestroy(stage2T);
        cudaEventDestroy(stage3T);
        cudaEventDestroy(stopT);
    }

    // Validate and report    
    {
        printf("\rValidation Status: \n");
        printf("\tImage width: %s" CONSOLE_RESET "\n", validation_image.width == output_image.width ? CONSOLE_GREEN "Pass" : CONSOLE_RED "Fail");
        printf("\tImage height: %s" CONSOLE_RESET "\n", validation_image.height == output_image.height ? CONSOLE_GREEN "Pass" : CONSOLE_RED "Fail");
        int v_size = validation_image.width * validation_image.height;
        int o_size = output_image.width * output_image.height;
        int s_size = v_size < o_size ? v_size : o_size;
        int bad_pixels = 0;
        int close_pixels = 0;
        if (output_image.data && s_size) {
            for (int i = 0; i < s_size; ++i) {
                if (output_image.data[i] != validation_image.data[i]) {
                    // Give a +-1 threshold for error (incase fast-math triggers a small difference in places)
                    if (output_image.data[i]+1 == validation_image.data[i] || output_image.data[i]-1 == validation_image.data[i]) {
                        close_pixels++;
                    } else {
                        bad_pixels++;
                    }
                }
            }
            printf("\tImage pixels: ");
            if (bad_pixels) {
                printf(CONSOLE_RED "Fail" CONSOLE_RESET " (%d/%u wrong)\n", bad_pixels, o_size);
            } else {
                printf(CONSOLE_GREEN "Pass" CONSOLE_RESET "\n");
            }
        } else {
            printf("\tImage pixels: " CONSOLE_RED "Fail" CONSOLE_RESET "\n");
        }
    }

    // Export output image
    if (config.output_file) {
        if (!stbi_write_png(config.output_file, output_image.width, output_image.height, output_image.channels, output_image.data, output_image.width * output_image.channels)) {
            printf(CONSOLE_YELLOW "Unable to save image output to %s.\n" CONSOLE_RESET, config.output_file);
            // return EXIT_FAILURE;
        }
    }


    // Report timing information    
    printf("%s Average execution timing from %d runs\n", mode_to_string(config.mode), TOTAL_RUNS);
    if (config.mode == CUDA) {
        int device_id = 0;
        CUDA_CALL(cudaGetDevice(&device_id));
        cudaDeviceProp props;
        memset(&props, 0, sizeof(cudaDeviceProp));
        CUDA_CALL(cudaGetDeviceProperties(&props, device_id));
        printf("Using GPU: %s\n", props.name);
    }
#ifdef _DEBUG
    printf(CONSOLE_YELLOW "Code built as DEBUG, timing results are invalid!\n" CONSOLE_RESET);
#endif
    printf("Init: %.3fms\n", timing_log.init);
    printf("Stage 1: %.3fms%s\n", timing_log.stage1, getStage1SkipUsed() ? CONSOLE_YELLOW " (helper method used, time invalid)" CONSOLE_RESET : "");
    printf("Stage 2: %.3fms%s\n", timing_log.stage2, getStage2SkipUsed() ? CONSOLE_YELLOW " (helper method used, time invalid)" CONSOLE_RESET : "");
    printf("Stage 3: %.3fms%s\n", timing_log.stage3, getStage3SkipUsed() ? CONSOLE_YELLOW " (helper method used, time invalid)" CONSOLE_RESET : "");
    printf("Free: %.3fms\n", timing_log.cleanup);
    printf("Total: %.3fms%s\n", timing_log.total, getSkipUsed() ? CONSOLE_YELLOW " (helper method used, time invalid)" CONSOLE_RESET : "");

    // Cleanup
    cudaDeviceReset();
    free(validation_image.data);
    free(particles);
    free(output_image.data);
    free(config.input_file);
    if (config.output_file)
        free(config.output_file);
    return EXIT_SUCCESS;
}
void parse_args(int argc, char **argv, Config *config) {
    // Clear config struct
    memset(config, 0, sizeof(Config));
    if (argc < 3 || argc > 5) {
        fprintf(stderr, "Program expects 2-4 arguments, only %d provided.\n", argc-1);
        print_help(argv[0]);
    }
    // Parse first arg as mode
    {
        char lower_arg[7];  // We only care about first 6 characters
        // Convert to lower case
        int i = 0;
        for(; argv[1][i] && i < 6; i++){
            lower_arg[i] = tolower(argv[1][i]);
        }
        lower_arg[i] = '\0';
        // Check for a match
        if (!strcmp(lower_arg, "cpu")) {
            config->mode = CPU;
        } else if (!strcmp(lower_arg, "openmp")) {
            config->mode = OPENMP;
        } else if (!strcmp(lower_arg, "cuda") || !strcmp(lower_arg, "gpu")) {
            config->mode = CUDA;
        } else {
            fprintf(stderr, "Unexpected string provided as first argument: '%s' .\n", argv[1]);
            fprintf(stderr, "First argument expects a single mode as string: CPU, OPENMP, CUDA.\n");
            print_help(argv[0]);
        }
    }
    // Parse second arg as input file
    {
        // Find length of string
        const size_t input_name_len = strlen(argv[2]) + 1;  // Add 1 for null terminating character
        // Allocate memory and copy
        config->input_file = (char*)malloc(input_name_len);
        memcpy(config->input_file, argv[2], input_name_len);
    }
    
    // Iterate over remaining args    
    int i = 3;
    char * t_arg = 0;
    for (; i < argc; i++) {
        // Make a lowercase copy of the argument
        const size_t arg_len = strlen(argv[i]) + 1;  // Add 1 for null terminating character
        if (t_arg) 
            free(t_arg);
        t_arg = (char*)malloc(arg_len);
        int j = 0;
        for(; argv[i][j]; ++j){
            t_arg[j] = tolower(argv[i][j]);
        }
        t_arg[j] = '\0';
        // Decide which arg it is
        if (!strcmp("--bench", t_arg) || !strcmp("--benchmark", t_arg)|| !strcmp("-b", t_arg)) {
            config->benchmark = 1;
            continue;
        }
        if (!strcmp(t_arg + arg_len - 5, ".png")) {
            // Allocate memory and copy
            config->output_file = (char*)malloc(arg_len);
            memcpy(config->output_file, argv[i], arg_len);
            continue;
        }
        fprintf(stderr, "Unexpected optional argument: %s\n", argv[i]);
        print_help(argv[0]);
    }
    if (t_arg) 
        free(t_arg);
}
void print_help(const char *program_name) {
    fprintf(stderr, "%s <mode> <input image> (<output image>) (--bench)\n", program_name);
    
    const char *line_fmt = "%-18s %s\n";
    fprintf(stderr, "Required Arguments:\n");
    fprintf(stderr, line_fmt, "<mode>", "The algorithm to use: CPU, OPENMP, CUDA");
    fprintf(stderr, line_fmt, "<input image>", "Input image, .png, .jpg");
    fprintf(stderr, "Optional Arguments:\n");
    fprintf(stderr, line_fmt, "<output image>", "Output image, requires .png filetype");
    fprintf(stderr, line_fmt, "-b, --bench", "Enable benchmark mode");

    exit(EXIT_FAILURE);
}
const char *mode_to_string(Mode m) {
    switch (m)
    {
    case CPU:
      return "CPU";
    case OPENMP:
     return "OpenMP";
    case CUDA:
      return "CUDA";
    }
    return "?";
}
