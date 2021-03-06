#include "../include/sift.h"
#include "cuda_runtime.h"
#include "../include/utils.h"
#define HANDLE_ERROR(err) (HandleError(err, __FILE__, __LINE__));


namespace sift
{

	__global__ void kernel_detect_extreme(float *** dog_pyramid_gpu, int *** mask_gpu, int **row_col_gpu,
		int total_interval)
	{
		//printf("blockDim.x = %d\n", blockDim.x);
		int cur_oct = blockIdx.x;
		int cur_interval = blockIdx.y;
		int cur_block = blockIdx.z;
		int thread_num = threadIdx.x;
		// the first/last interval of each layer
		if (cur_interval == 0 || cur_interval == total_interval + 1)
		{
			return;
		}

		// remove out of the img and img border point
		int img_row = row_col_gpu[cur_oct][0];
		int img_col = row_col_gpu[cur_oct][1];
		int cur_index = threadIdx.x + blockDim.x * cur_block;

		int cur_row = cur_index / img_col;
		int cur_col = cur_index % img_col;
		if (cur_row == 0 || cur_row >= img_row - 1 || cur_col == 0 || cur_col >= img_col - 1)
		{
			return;
		}
		// start detecting extreme point
		float max_delta = -10;
		float min_delta = 10;
		float value = dog_pyramid_gpu[cur_oct][cur_interval][cur_index];
		for (int delta_sigma = -1; delta_sigma < 2; ++delta_sigma)
		{
			for (int row_delta = -1; row_delta < 2; ++row_delta) {
				for (int col_delta = -1; col_delta < 2; ++col_delta) {
					int linshi_row = cur_row + row_delta;
					int linshi_col = cur_col + col_delta;
					int linshi_index = linshi_row * img_col + linshi_col;
					float delta = dog_pyramid_gpu[cur_oct][cur_interval + delta_sigma][linshi_index] - value;
					if (delta < min_delta)
					{
						min_delta = delta;
					}
					if (delta > max_delta)
					{
						max_delta = delta;
					}
				}
			}
		}
		// extreme point
		if (max_delta < 1e-3 || max_delta > -1e-3 || min_delta < 1e-3 || min_delta > 1e-3)
		{
			//printf("cur_oct = %d, cur_interval = %d\n", cur_oct, cur_interval);
			mask_gpu[cur_oct][cur_interval][cur_index] = 1;
		}
	};

	// gpu上的指针不能用数组下标[]进行初始化
	void detect_extreme_point(cv::Mat *** dog_pyramid, int **** mask_cpu, int octvs, int intervals)
	{
		float *** dog_pyramid_cpu = (float ***)malloc(octvs * sizeof(float**));
		*mask_cpu = (int ***)calloc(octvs, sizeof(int **));
		int ** row_col_cpu = (int **)malloc(octvs * sizeof(int *));

		for (int o = 0; o < octvs; ++o)
		{
			(*mask_cpu)[o] = (int **)calloc(intervals, sizeof(int *));
			dog_pyramid_cpu[o] = (float **)malloc((intervals + 2) * sizeof(float *));
			int rows = dog_pyramid[o][0]->rows;
			int cols = dog_pyramid[o][0]->cols;
			row_col_cpu[o] = (int *)malloc(2 * sizeof(int));
			row_col_cpu[o][0] = rows;
			row_col_cpu[o][0] = cols;

			size_t img_size = rows * cols * sizeof(float);
			for (int i = 0; i < intervals + 2; ++i)
			{
				(*mask_cpu)[o][i] = (int *)calloc(rows * cols, sizeof(int));
				dog_pyramid_cpu[o][i] = (float *)malloc(img_size);
				for (int index = 0; index < rows*cols; ++index) {
					dog_pyramid_cpu[o][i][index] = dog_pyramid[o][i]->data[index];
				}
			}
		}
		// //////////////////////////////////////////////////////////////////
		// allocate gpu memory and cpy from cpu to gpu
		// //////////////////////////////////////////////////////////////////
		float *** dog_pyramid_gpu = NULL;
		int *** mask_gpu = NULL;
		int ** row_col_gpu = NULL;
		HANDLE_ERROR(cudaSetDevice(0));
		HANDLE_ERROR(cudaMalloc((void **)&dog_pyramid_gpu, octvs * sizeof(float**)));
		HANDLE_ERROR(cudaMalloc((void **)&mask_gpu, octvs * sizeof(int**)));
		HANDLE_ERROR(cudaMalloc((void **)&row_col_gpu, octvs * sizeof(int*)));

		// ///////////////////////////////////////////////////////////////
		// allocate block and grid
		// ///////////////////////////////////////////////////////////////
		int num = getThreadNum();
		int origin_rows = dog_pyramid[0][0]->rows;
		int origin_cols = dog_pyramid[0][0]->cols;
		int block_dim_y = (origin_rows * origin_cols - 1) / num + 1;
		dim3 thread_grid_size(octvs, intervals + 2, block_dim_y);
		dim3 thread_block_size(num, 1, 1);

		sift::kernel_detect_extreme << <thread_block_size, thread_grid_size >> > (dog_pyramid_gpu, mask_gpu, row_col_gpu, intervals);

		// cpy from gpu to cpu
		HANDLE_ERROR(cudaMemcpy(*mask_cpu, mask_gpu, octvs * sizeof(int **), cudaMemcpyDeviceToHost));

		// release gpu memory
		HANDLE_ERROR(cudaFree(dog_pyramid_gpu));
		HANDLE_ERROR(cudaFree(mask_gpu));
		HANDLE_ERROR(cudaFree(row_col_gpu));

		// release cpu memory
		for (int o = 0; o < octvs; ++o)
		{
			free(row_col_cpu[o]);
			for (int i = 0; i < intervals + 2; ++i)
			{
				free(dog_pyramid_cpu[o][i]);
			}
			free(dog_pyramid_cpu[o]);
		}
		free(row_col_cpu);
		free(dog_pyramid_cpu);


		HANDLE_ERROR(cudaDeviceReset());
	};


	// to deal with high dimension array, one way is two flatten to 1D array, another is as followings.
	//void detect_extreme_point(float *** dog_pyramid_cpu, int **** mask_cpu, int ** row_col_cpu, int octvs, int intervals)
	//{
	//	HANDLE_ERROR(cudaSetDevice(0));
	//	 //////////////////////////////////////////////////////////////////
	//	 allocate gpu memory and cpy from cpu to gpu
	//	 //////////////////////////////////////////////////////////////////
	//	float *** dog_pyramid_gpu = NULL;
	//	int *** mask_gpu = NULL;
	//	int ** row_col_gpu = NULL;

	//	HANDLE_ERROR(cudaMalloc((void ****)&mask_gpu, octvs * sizeof(int**)));
	//	HANDLE_ERROR(cudaMalloc((void ****)&dog_pyramid_gpu, octvs * sizeof(float**)));
	//	HANDLE_ERROR(cudaMalloc((void ***)&row_col_gpu, octvs * sizeof(int*)));
	//	float *** total_dog_pyramid_cpu = (float ***)malloc(octvs * sizeof(float **));
	//	int *** mask_cpu_total = (int ***)malloc(octvs * sizeof(int **));
	//	int ** cpu_row_col_total = (int **)malloc(octvs * sizeof(int *));
	//	size_t mask_size = 0;
	//	for (int o = 0; o < octvs; ++o)
	//	{
	//		int pixel_num = row_col_cpu[o][0] * row_col_cpu[o][1];
	//		mask_size += (intervals + 2) *pixel_num * sizeof(int);

	//		int ** intervals_mask_gpu;
	//		int ** intervals_mask_cpu = (int **)malloc((intervals + 2) * sizeof(int*));
	//		HANDLE_ERROR(cudaMalloc((void ***)&(intervals_mask_gpu), (intervals + 2) * sizeof(int*)));
	//		float ** intervals_pyramid_gpu;
	//		float ** intervals_pyramid_cpu = (float **)malloc((intervals + 2) * sizeof(float*));
	//		HANDLE_ERROR(cudaMalloc((void ***)&(intervals_pyramid_gpu), (intervals + 2) * sizeof(float*)));
	//		int * interval_row_gpu;
	//		HANDLE_ERROR(cudaMalloc((void **)&(interval_row_gpu), 2 * sizeof(int)));
	//		HANDLE_ERROR(cudaMemcpy(interval_row_gpu, row_col_cpu[o], 2 * sizeof(int), cudaMemcpyHostToDevice));
	//		cpu_row_col_total[o] = interval_row_gpu;
	//		for (int i = 0; i < intervals + 2; ++i)
	//		{

	//			int * pixel_mask_gpu;
	//			int * pixel_mask_cpu = (int *)calloc(pixel_num, sizeof(int));
	//			HANDLE_ERROR(cudaMalloc((void **)&pixel_mask_gpu, pixel_num * sizeof(int)));
	//			HANDLE_ERROR(cudaMemcpy(pixel_mask_gpu, pixel_mask_cpu, pixel_num * sizeof(int), cudaMemcpyHostToDevice));
	//			intervals_mask_cpu[i] = pixel_mask_gpu;
	//			float * dog_pixel_gpu;
	//			HANDLE_ERROR(cudaMalloc((void **)&dog_pixel_gpu, pixel_num * sizeof(float)));
	//			HANDLE_ERROR(cudaMemcpy(dog_pixel_gpu, dog_pyramid_cpu[o][i], pixel_num * sizeof(float), cudaMemcpyHostToDevice));
	//			intervals_pyramid_cpu[i] = dog_pixel_gpu;
	//			 release memory on the heap
	//			free(pixel_mask_cpu);
	//		}
	//		HANDLE_ERROR(cudaMemcpy(intervals_pyramid_gpu, intervals_pyramid_cpu,
	//			(intervals + 2) * sizeof(float*), cudaMemcpyHostToDevice));
	//		HANDLE_ERROR(cudaMemcpy(intervals_mask_gpu, intervals_mask_cpu,
	//			(intervals + 2) * sizeof(int*), cudaMemcpyHostToDevice));


	//		total_dog_pyramid_cpu[o] = intervals_pyramid_gpu;
	//		mask_cpu_total[o] = intervals_mask_gpu;

	//		 release memory
	//		/*for (int i = 0; i < intervals + 2; ++i)
	//		{
	//			HANDLE_ERROR(cudaFree(intervals_pyramid_cpu[i]));
	//			HANDLE_ERROR(cudaFree(intervals_mask_cpu[i]));
	//		}*/
	//		free(intervals_mask_cpu);
	//		free(intervals_pyramid_cpu);
	//	}
	//	HANDLE_ERROR(cudaMemcpy(mask_gpu, mask_cpu_total, octvs * sizeof(int**), cudaMemcpyHostToDevice));
	//	HANDLE_ERROR(cudaMemcpy(dog_pyramid_gpu, total_dog_pyramid_cpu, octvs * sizeof(float**), cudaMemcpyHostToDevice));
	//	HANDLE_ERROR(cudaMemcpy(row_col_gpu, cpu_row_col_total, octvs * sizeof(int*), cudaMemcpyHostToDevice));

	//	 ///////////////////////////////////////////////////////////////
	//	 allocate block and grid
	//	 ///////////////////////////////////////////////////////////////
	//	int num = getThreadNum();
	//	int origin_rows = row_col_cpu[0][0];
	//	int origin_cols = row_col_cpu[0][1];
	//	int block_dim_z = (origin_rows * origin_cols - 1) / num + 1;
	//	printf("grid.x = %d, grid.y = %d, grid.z = %d", octvs, intervals + 2, block_dim_z);
	//	dim3 thread_grid_size(octvs, intervals + 2, block_dim_z);
	//	dim3 thread_block_size(num, 1, 1);

	//	sift::kernel_detect_extreme << < thread_grid_size, thread_block_size >> > (dog_pyramid_gpu, mask_gpu, row_col_gpu, intervals);

	//	 cpy from gpu to cpu
	//	*mask_cpu = (int ***)malloc(octvs * sizeof(int **));
	//	
	//	for (int o = 0; o < octvs; ++o)
	//	{
	//		int pixel_num = row_col_cpu[o][0] * row_col_cpu[o][1];
	//		(*mask_cpu)[o] = (int **)malloc(intervals + 2 * sizeof(int *));
	//		for (int i = 0; i < intervals + 2; ++i)
	//		{
	//			(*mask_cpu)[o][i] = (int *)malloc(pixel_num * sizeof(int));
	//			//HANDLE_ERROR(cudaMemcpy((*mask_cpu)[o][i], mask_gpu, octvs * sizeof(int**), cudaMemcpyDeviceToHost));
	//		}
	//	}
	//	int * linshi_mask_cpu = (int *)malloc(mask_size);
	//	HANDLE_ERROR(cudaMemcpy(linshi_mask_cpu, mask_gpu, mask_size, cudaMemcpyDeviceToHost));
	//	printf("linshi_mask_cpu[0] = %d\n", linshi_mask_cpu[0]);

	//	printf("(*linshi_mask_cpu)[0][0][0] = %d\n", (*mask_cpu)[0]);
	//	 release memory
	//	/*for (int o = 0; o < octvs; ++o)
	//	{
	//		HANDLE_ERROR(cudaFree(mask_cpu_total[o]));
	//		HANDLE_ERROR(cudaFree(total_dog_pyramid_cpu[o]));
	//	}*/

	//	free(total_dog_pyramid_cpu);
	//	free(mask_cpu_total);
	//	free(cpu_row_col_total);
	//	HANDLE_ERROR(cudaFree(dog_pyramid_gpu));
	//	HANDLE_ERROR(cudaFree(mask_gpu));
	//	HANDLE_ERROR(cudaFree(row_col_gpu));

	//	HANDLE_ERROR(cudaDeviceReset());
	//};

	// to deal with high dimension array, one way is two flatten to 1D array, another is as followings.
	void detect_extreme_point(float *** dog_pyramid_cpu, int **** mask_cpu, int ** row_col_cpu, int octvs, int intervals)
	{
		HANDLE_ERROR(cudaSetDevice(0));
		// //////////////////////////////////////////////////////////////////
		// allocate gpu memory and cpy from cpu to gpu
		// //////////////////////////////////////////////////////////////////
		float * dog_pyramid_gpu = NULL;
		int * mask_gpu = NULL;
		int * row_col_gpu = NULL;


		HANDLE_ERROR(cudaMalloc((void **)&mask_gpu, octvs * sizeof(int**)));
		HANDLE_ERROR(cudaMalloc((void **)&dog_pyramid_gpu, octvs * sizeof(float**)));

		HANDLE_ERROR(cudaMalloc((void **)&row_col_gpu, octvs * 2 * sizeof(int)));
		HANDLE_ERROR(cudaMemcpy(row_col_gpu, row_col_cpu[0], 2 * sizeof(int) * octvs, cudaMemcpyHostToDevice));


		// ///////////////////////////////////////////////////////////////
		// allocate block and grid
		// ///////////////////////////////////////////////////////////////
		int num = getThreadNum();
		int origin_rows = row_col_cpu[0][0];
		int origin_cols = row_col_cpu[0][1];
		int block_dim_z = (origin_rows * origin_cols - 1) / num + 1;
		printf("grid.x = %d, grid.y = %d, grid.z = %d", octvs, intervals + 2, block_dim_z);
		dim3 thread_grid_size(octvs, intervals + 2, block_dim_z);
		dim3 thread_block_size(num, 1, 1);

		//sift::kernel_detect_extreme << < thread_grid_size, thread_block_size >> > (dog_pyramid_gpu, mask_gpu, row_col_gpu, intervals);



		//free(total_dog_pyramid_cpu);
		//free(mask_cpu_total);
		//free(cpu_row_col_total);
		//HANDLE_ERROR(cudaFree(dog_pyramid_gpu));
		//HANDLE_ERROR(cudaFree(mask_gpu));
		//HANDLE_ERROR(cudaFree(row_col_gpu));

		//HANDLE_ERROR(cudaDeviceReset());
	}
} // namespace sift


