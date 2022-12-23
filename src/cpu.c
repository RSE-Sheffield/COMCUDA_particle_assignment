#include "cpu.h"
#include "helper.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

///
/// Utility Methods
///
/**
 * Simple (inplace) quicksort pair sort implementation
 * Items at the matching index within keys and values are sorted according to keys in ascending order
 * @param keys_start Pointer to the start of the keys (depth) buffer
 * @param colours_start Pointer to the start of the values (colours) buffer (each color consists of three unsigned char)
 * @param count Number of items from the pointer to pair sort
 * @note This function is implemented at the bottom of cpu.c
 */
void sort_pairs(float* keys_start, unsigned char* colours_start, int count);


///
/// Algorithm storage
///
unsigned int cpu_particles_count;
Particle *cpu_particles;
unsigned int *cpu_pixel_contribs;
unsigned int *cpu_pixel_index;
unsigned char *cpu_pixel_contrib_colours;
float *cpu_pixel_contrib_depth;
unsigned int cpu_pixel_contrib_count;
CImage cpu_output_image;

///
/// Implementation
///
void cpu_begin(const Particle* init_particles, const unsigned int init_particles_count) {
    // Allocate a opy of the initial particles, to be used during computation
    cpu_particles_count = init_particles_count;
    cpu_particles = malloc(init_particles_count * sizeof(Particle));
    memcpy(cpu_particles, init_particles, init_particles_count * sizeof(Particle));

    // Allocate a histogram to track how many particles contribute to each pixel
    cpu_pixel_contribs = (unsigned int *)malloc(OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT * sizeof(unsigned int));
    // Allocate an index to track where data for each pixel's contributing colour starts
    cpu_pixel_index = (unsigned int*)malloc((OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT + 1) * sizeof(unsigned int));
    // Init a buffer to store colours contributing to each pixel into (allocated in stage 2)
    cpu_pixel_contrib_colours = 0;
    // Init a buffer to store depth of colours contributing to each pixel into (allocated in stage 2)
    cpu_pixel_contrib_depth = 0;
    // This tracks the number of contributes the two above buffers are allocated for, init 0
    cpu_pixel_contrib_count = 0;



    // Allocate output image
    cpu_output_image.width = OUT_IMAGE_WIDTH;
    cpu_output_image.height = OUT_IMAGE_HEIGHT;
    cpu_output_image.channels = 3;
    cpu_output_image.data = (unsigned char *)malloc(cpu_output_image.width * cpu_output_image.height * cpu_output_image.channels * sizeof(unsigned char));
}
void cpu_stage1() {
    // Reset the pixel contributions histogram
    memset(cpu_pixel_contribs, 0, OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT * sizeof(unsigned int));
    // Update each particle & calculate how many particles contribute to each image
    for (unsigned int i = 0; i < cpu_particles_count; ++i) {
        // Update position in the x & y axis (particle depth never changes)
        cpu_particles[i].location[0] += cpu_particles[i].direction[0] * cpu_particles[i].speed;
        cpu_particles[i].location[1] += cpu_particles[i].direction[1] * cpu_particles[i].speed;
        // @TODO, wrap particles that exceed image bounds
        // @TODO, update direction?
        if (cpu_particles[i].type == Square) {
            // Compute bounding box [inclusive-inclusive]
            int x_min = (int)roundf(cpu_particles[i].location[0] - cpu_particles[i].radius);
            int y_min = (int)roundf(cpu_particles[i].location[1] - cpu_particles[i].radius);
            int x_max = (int)roundf(cpu_particles[i].location[0] + cpu_particles[i].radius);
            int y_max = (int)roundf(cpu_particles[i].location[1] + cpu_particles[i].radius);
            // Clamp bounding box to image bounds
            x_min = x_min < 0 ? 0 : x_min;
            y_min = y_min < 0 ? 0 : y_min;
            x_max = x_max >= OUT_IMAGE_WIDTH ? OUT_IMAGE_WIDTH - 1 : x_max;
            y_max = y_max >= OUT_IMAGE_HEIGHT ? OUT_IMAGE_HEIGHT - 1 : y_max;
            // Notify every pixel within the bounding box
            for (int x = x_min; x < x_max; ++x) {
                for (int y = y_min; y < y_max; ++y) {
                    const unsigned int pixel_offset = y * OUT_IMAGE_WIDTH + x;
                    ++cpu_pixel_contribs[pixel_offset];
                }
            }
        } else if(cpu_particles[i].type == Circle) {
            //@TODO
            // Compute bounding box

            // Notify every pixel within the bounding box
            
        }
    }
}
void cpu_stage2() {
    // Exclusive prefix sum across the histogram to create an index
    cpu_pixel_index[0] = 0;
    for (unsigned int i = 0; i < OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT; ++i) {
        cpu_pixel_index[i + 1] = cpu_pixel_index[i] + cpu_pixel_contribs[i];
    }
    // Recover the total from the index
    const unsigned int TOTAL_CONTRIBS = cpu_pixel_index[OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT];
    if (TOTAL_CONTRIBS > cpu_pixel_contrib_count) {
        // (Re)Allocate colour storage
        if (cpu_pixel_contrib_colours) free(cpu_pixel_contrib_colours);
        if (cpu_pixel_contrib_depth) free(cpu_pixel_contrib_depth);
        cpu_pixel_contrib_colours = (unsigned char*)malloc(TOTAL_CONTRIBS * 4 * sizeof(unsigned char));
        cpu_pixel_contrib_depth = (float*)malloc(TOTAL_CONTRIBS * sizeof(float));
        cpu_pixel_contrib_count = TOTAL_CONTRIBS;
    }

    // Reset the pixel contributions histogram
    memset(cpu_pixel_contribs, 0, OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT * sizeof(unsigned int));
    // Store colours according to index
    // For each particle, store a copy of the colour/depth in cpu_pixel_contribs for each contributed pixel
    for (unsigned int i = 0; i < cpu_particles_count; ++i) {
        if (cpu_particles[i].type == Square) {
            // Compute bounding box [inclusive-inclusive]
            int x_min = (int)roundf(cpu_particles[i].location[0] - cpu_particles[i].radius);
            int y_min = (int)roundf(cpu_particles[i].location[1] - cpu_particles[i].radius);
            int x_max = (int)roundf(cpu_particles[i].location[0] + cpu_particles[i].radius);
            int y_max = (int)roundf(cpu_particles[i].location[1] + cpu_particles[i].radius);
            // Clamp bounding box to image bounds
            x_min = x_min < 0 ? 0 : x_min;
            y_min = y_min < 0 ? 0 : y_min;
            x_max = x_max >= OUT_IMAGE_WIDTH ? OUT_IMAGE_WIDTH - 1 : x_max;
            y_max = y_max >= OUT_IMAGE_HEIGHT ? OUT_IMAGE_HEIGHT - 1 : y_max;
            // Store data for every pixel within the bounding box
            for (int x = x_min; x < x_max; ++x) {
                for (int y = y_min; y < y_max; ++y) {
                    const unsigned int pixel_offset = y * OUT_IMAGE_WIDTH + x;
                    // Offset into cpu_pixel_contrib buffers is index + histogram
                    // Increment cpu_pixel_contribs, so next contributor stores to correct offset
                    const unsigned int storage_offset = cpu_pixel_index[pixel_offset] + (cpu_pixel_contribs[pixel_offset]++);
                    // Copy data to cpu_pixel_contrib buffers
                    memcpy(cpu_pixel_contrib_colours + (4 * storage_offset), cpu_particles->color, 4 * sizeof(unsigned char));
                    memcpy(cpu_pixel_contrib_depth + storage_offset, &cpu_particles->location[2], sizeof(float));
                }
            }
        } else if(cpu_particles[i].type == Circle) {
            // @TODO
        }
    }

    // Pair sort the colours contributing to each pixel based on ascending depth
    for (unsigned int i = 0; i < OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT; ++i) {
        int data_count = cpu_pixel_index[i + 1] - cpu_pixel_index[i];
        // Pair sort the colours which contribute to a single pigment
        sort_pairs(
            cpu_pixel_contrib_depth,
            cpu_pixel_contrib_colours,
            data_count
        );
    }
}
void cpu_stage3() {
    // Memset output image data to 0 (black)
    memset(cpu_output_image.data, 0, cpu_output_image.width * cpu_output_image.height * cpu_output_image.channels * sizeof(unsigned char));

    // Order dependent blending into output image
    for (unsigned int i = 0; i < OUT_IMAGE_WIDTH * OUT_IMAGE_HEIGHT; ++i) {
        for (unsigned int j = cpu_pixel_index[i]; j < cpu_pixel_index[i + 1]; ++j) {
            // Blend each of the red/green/blue colours according to the below blend formula
            // dest = src * opacity + dest * (1 - opacity);
            const float opacity = (float)cpu_pixel_contrib_colours[j * 4 + 3]/ (float)255;
            cpu_output_image.data[(i * 3) + 0] = (unsigned char)((float)cpu_pixel_contrib_colours[j * 4 + 0] * opacity + (float)cpu_output_image.data[(i * 3) + 0] * (1 - opacity));
            cpu_output_image.data[(i * 3) + 1] = (unsigned char)((float)cpu_pixel_contrib_colours[j * 4 + 1] * opacity + (float)cpu_output_image.data[(i * 3) + 1] * (1 - opacity));
            cpu_output_image.data[(i * 3) + 2] = (unsigned char)((float)cpu_pixel_contrib_colours[j * 4 + 2] * opacity + (float)cpu_output_image.data[(i * 3) + 2] * (1 - opacity));
        }
    }
}
void cpu_end(CImage *output_image) {
    // Store return value
    output_image->width = cpu_output_image.width;
    output_image->height = cpu_output_image.height;
    output_image->channels = cpu_output_image.channels;
    memcpy(output_image->data, cpu_output_image.data, cpu_output_image.width * cpu_output_image.height * cpu_output_image.channels * sizeof(unsigned char));
    // Release allocations
    free(cpu_pixel_contrib_depth);
    free(cpu_pixel_contrib_colours);
    free(cpu_output_image.data);
    free(cpu_pixel_index);
    free(cpu_pixel_contribs);
    free(cpu_particles);
    // Return ptrs to nullptr
    cpu_pixel_contrib_depth = 0;
    cpu_pixel_contrib_colours = 0;
    cpu_output_image.data = 0;
    cpu_pixel_index = 0;
    cpu_pixel_contribs = 0;
    cpu_particles = 0;
}

void sort_pairs(float* keys_start, unsigned char* colours_start, const int last, const int first) {
    // Based on https://www.tutorialspoint.com/explain-the-quick-sort-technique-in-c-language
    int i, j, pivot;
    float depth_t;
    unsigned char color_t[4];
    if (first < last) {
        pivot = first;
        i = first;
        j = last;
        while (i < j) {
            while (keys_start[i] <= keys_start[pivot] && i < last)
                i++;
            while (keys_start[j] > keys_start[pivot])
                j--;
            if (i < j) {
                // Swap key
                depth_t = keys_start[i];
                keys_start[i] = keys_start[j];
                keys_start[j] = depth_t;
                // Swap color
                memcpy(color_t, colours_start + (4 * i), 4 * sizeof(unsigned char));
                memcpy(colours_start + (4 * i), colours_start + (4 * j), 4 * sizeof(unsigned char));
                memcpy(colours_start + (4 * j), color_t, 4 * sizeof(unsigned char));
            }
        }
        // Swap key
        depth_t = keys_start[pivot];
        keys_start[pivot] = keys_start[j];
        keys_start[j] = depth_t;
        // Swap color
        memcpy(color_t, colours_start + (4 * pivot), 4 * sizeof(unsigned char));
        memcpy(colours_start + (4 * pivot), colours_start + (4 * j), 4 * sizeof(unsigned char));
        memcpy(colours_start + (4 * j), color_t, 4 * sizeof(unsigned char));
        // Recurse
        sort_pairs(keys_start, colours_start, first, j - 1);
        sort_pairs(keys_start, colours_start, j + 1, last);
    }
}
void sort_pairs(float* keys_start, unsigned char* colours_start, const int count) {
    sort_pairs(keys_start, colours_start, count, 0);
}
