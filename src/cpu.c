#include "cpu.h"
#include "helper.h"

#include <stdlib.h>
#include <string.h>

///
/// Utility Methods
///



///
/// Algorithm storage
///
unsigned int cpu_particles_count;
Particle *cpu_particles;
CImage cpu_output_image;

///
/// Implementation
///
void cpu_begin(const Particle* init_particles, const unsigned int init_particles_count) {
    // Allocate a opy of the initial particles, to be used during computation
    cpu_particles_count = init_particles_count;
    cpu_particles = malloc(init_particles_count * sizeof(Particle));
    memcpy(cpu_particles, init_particles, init_particles_count * sizeof(Particle));

    // Allocate output image
    cpu_output_image.width = OUT_IMAGE_WIDTH;
    cpu_output_image.height = OUT_IMAGE_HEIGHT;
    cpu_output_image.channels = 3;
    cpu_output_image.data = (unsigned char *)malloc(cpu_output_image.width * cpu_output_image.height * cpu_output_image.channels * sizeof(unsigned char));
}
void cpu_stage1() {
    
}
void cpu_stage2() {
    
}
void cpu_stage3() {
    
}
void cpu_end(CImage *output_image) {
    // Store return value
    output_image->width = cpu_output_image.width;
    output_image->height = cpu_output_image.height;
    output_image->channels = cpu_output_image.channels;
    memcpy(output_image->data, cpu_output_image.data, cpu_output_image.width * cpu_output_image.height * cpu_output_image.channels * sizeof(unsigned char));
    // Release allocations
    free(cpu_output_image.data);
    free(cpu_particles);
    // Return ptrs to nullptr
    cpu_output_image.data = 0;
    cpu_particles = 0;
}
