#include "openmp.h"
#include "helper.h"

#include <stdlib.h>
#include <string.h>
#include <omp.h>
#include <math.h>

void openmp_begin(const Particle* init_particles, const unsigned int init_particles_count,
    const unsigned int out_image_width, const unsigned int out_image_height) {

}
void openmp_stage1() {
    // Optionally during development call the skip function with the correct inputs to skip this stage
    // skip_pixel_contribs(particles, particles_count, return_pixel_contribs, out_image_width, out_image_height);

#ifdef VALIDATION
    // TODO: Uncomment and call the validation function with the correct inputs
    // validate_pixel_contribs(particles, particles_count, pixel_contribs, out_image_width, out_image_height);
#endif
}
void openmp_stage2() {
    // Optionally during development call the skip function/s with the correct inputs to skip this stage
    // skip_pixel_index(pixel_contribs, return_pixel_index, out_image_width, out_image_height);
    // skip_sorted_pairs(particles, particles_count, pixel_index, out_image_width, out_image_height, return_pixel_contrib_colours, return_pixel_contrib_depth);

#ifdef VALIDATION
    // TODO: Uncomment and call the validation functions with the correct inputs
    // Note: Only validate_equalised_histogram() MUST be uncommented, the others are optional
    // validate_pixel_index(pixel_contribs, pixel_index, output_image_width, cpu_output_image_height);
    // validate_sorted_pairs(particles, particles_count, pixel_index, output_image_width, cpu_output_image_height, pixel_contrib_colours, pixel_contrib_depth);
#endif    
}
void openmp_stage3() {
    // Optionally during development call the skip function with the correct inputs to skip this stage
    // skip_blend(pixel_index, pixel_contrib_colours, return_output_image);

#ifdef VALIDATION
    // TODO: Uncomment and call the validation function with the correct inputs
    // validate_blend(pixel_index, pixel_contrib_colours, &output_image);
#endif    
}
void openmp_end(CImage* output_image) {

}